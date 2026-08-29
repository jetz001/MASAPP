import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/db_helper.dart';
import '../../../core/ai/vector_db_service.dart';
import '../models/machine_plan_models.dart';

DateTime getMonday(DateTime date) {
  final weekday = date.weekday; // 1 = Monday, 7 = Sunday
  return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
}

DateTime getSunday(DateTime monday) {
  return monday.add(const Duration(days: 6));
}

class MachinePlanningState {
  final MachineWeeklyPlan plan;
  final bool isLoading;
  final String selectedBuilding; // 'ทั้งหมด' or specific building
  final String selectedRoom; // 'ทั้งหมด' or specific room
  final String searchQuery;

  const MachinePlanningState({
    required this.plan,
    this.isLoading = false,
    this.selectedBuilding = 'ทั้งหมด',
    this.selectedRoom = 'ทั้งหมด',
    this.searchQuery = '',
  });

  List<String> get availableBuildings {
    final set = <String>{'ทั้งหมด'};
    for (final item in plan.items) {
      if (item.building != null && item.building!.trim().isNotEmpty) {
        set.add(item.building!.trim());
      }
    }
    return set.toList();
  }

  List<String> get availableRooms {
    final set = <String>{'ทั้งหมด'};
    for (final item in plan.items) {
      if (item.room != null && item.room!.trim().isNotEmpty) {
        set.add(item.room!.trim());
      }
    }
    return set.toList();
  }

  List<MachinePlanItem> get filteredItems {
    return plan.items.where((item) {
      final matchesBuilding = selectedBuilding == 'ทั้งหมด' ||
          (item.building != null && item.building!.trim() == selectedBuilding);
      final matchesRoom = selectedRoom == 'ทั้งหมด' ||
          (item.room != null && item.room!.trim() == selectedRoom);

      if (!matchesBuilding || !matchesRoom) return false;

      if (searchQuery.trim().isEmpty) return true;
      final q = searchQuery.toLowerCase().trim();
      return item.machineName.toLowerCase().contains(q) ||
          item.machineCode.toLowerCase().contains(q) ||
          item.remarks.toLowerCase().contains(q) ||
          (item.room != null && item.room!.toLowerCase().contains(q)) ||
          (item.building != null && item.building!.toLowerCase().contains(q));
    }).toList();
  }

  MachinePlanningState copyWith({
    MachineWeeklyPlan? plan,
    bool? isLoading,
    String? selectedBuilding,
    String? selectedRoom,
    String? searchQuery,
  }) {
    return MachinePlanningState(
      plan: plan ?? this.plan,
      isLoading: isLoading ?? this.isLoading,
      selectedBuilding: selectedBuilding ?? this.selectedBuilding,
      selectedRoom: selectedRoom ?? this.selectedRoom,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class MachinePlanningNotifier extends StateNotifier<MachinePlanningState> {
  MachinePlanningNotifier()
      : super(MachinePlanningState(
          plan: _createDefaultPlan(DateTime.now()),
        )) {
    loadPlanForWeek(DateTime.now());
  }

  static MachineWeeklyPlan _createDefaultPlan(DateTime date) {
    final mon = getMonday(date);
    final sun = getSunday(mon);
    final startFmt = DateFormat('dd').format(mon);
    final endFmt = DateFormat('dd/MM').format(sun);
    final beYear = ((sun.year + 543) % 100).toString().padLeft(2, '0');
    final title = 'รายการ การใช้งานเครื่องจักร ประจำสัปดาห์ $startFmt-$endFmt/$beYear';

    return MachineWeeklyPlan(
      planId: const Uuid().v4(),
      weekStartDate: mon,
      weekEndDate: sun,
      title: title,
    );
  }

  Future<void> loadPlanForWeek(DateTime date) async {
    final mon = getMonday(date);
    final sun = getSunday(mon);
    final monStr = DateFormat('yyyy-MM-dd').format(mon);
    final sunStr = DateFormat('yyyy-MM-dd').format(sun);

    state = state.copyWith(isLoading: true);

    try {
      final planRows = await DbHelper.query(
        'SELECT * FROM machine_plans WHERE week_start_date = @mon LIMIT 1',
        params: {'mon': monStr},
      );

      MachineWeeklyPlan plan;
      if (planRows.isNotEmpty) {
        final row = planRows.first;
        final planId = row['plan_id'].toString();

        final itemRows = await DbHelper.query(
          'SELECT * FROM machine_plan_items WHERE plan_id = @id ORDER BY order_index ASC, created_at ASC',
          params: {'id': planId},
        );

        // Fetch station available backup machines
        final items = <MachinePlanItem>[];
        for (final itemRow in itemRows) {
          List<String> availableIds = [];
          final stationId = itemRow['station_id']?.toString();
          if (stationId != null && stationId.isNotEmpty) {
            final stRow = await DbHelper.queryOne(
              'SELECT machine_id, secondary_machine_ids FROM production_line_stations WHERE station_id = @stId',
              params: {'stId': stationId},
            );
            if (stRow != null) {
              final primary = stRow['machine_id']?.toString();
              if (primary != null && primary.isNotEmpty) {
                availableIds.add(primary);
              }
              if (stRow['secondary_machine_ids'] != null &&
                  stRow['secondary_machine_ids'].toString().isNotEmpty) {
                try {
                  final secList = List<String>.from(
                    jsonDecode(stRow['secondary_machine_ids']),
                  );
                  availableIds.addAll(secList);
                } catch (_) {}
              }
            }
          }
          if (!availableIds.contains(itemRow['machine_id']?.toString()) &&
              itemRow['machine_id'] != null) {
            availableIds.insert(0, itemRow['machine_id'].toString());
          }

          items.add(MachinePlanItem.fromMap(itemRow, availableIds: availableIds.toSet().toList()));
        }

        plan = MachineWeeklyPlan(
          planId: planId,
          weekStartDate: mon,
          weekEndDate: sun,
          title: row['title']?.toString() ?? 'แผนประจำสัปดาห์',
          note: row['note']?.toString(),
          items: items,
        );
      } else {
        // Create fresh empty plan for that week
        plan = _createDefaultPlan(mon);
        await DbHelper.execute('''
          INSERT INTO machine_plans (plan_id, week_start_date, week_end_date, title, note, created_at, updated_at)
          VALUES (@id, @start, @end, @title, @note, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ''', params: {
          'id': plan.planId,
          'start': monStr,
          'end': sunStr,
          'title': plan.title,
          'note': plan.note,
        });
      }

      state = state.copyWith(plan: plan, isLoading: false);
      if (plan.items.isNotEmpty) {
        VectorDbService.syncMachinePlan(plan.planId);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void nextWeek() {
    final nextMon = state.plan.weekStartDate.add(const Duration(days: 7));
    loadPlanForWeek(nextMon);
  }

  void prevWeek() {
    final prevMon = state.plan.weekStartDate.subtract(const Duration(days: 7));
    loadPlanForWeek(prevMon);
  }

  void setBuildingFilter(String building) {
    state = state.copyWith(selectedBuilding: building);
  }

  void setRoomFilter(String room) {
    state = state.copyWith(selectedRoom: room);
  }

  void setSearchQuery(String q) {
    state = state.copyWith(searchQuery: q);
  }

  Future<void> importFromLineBalancing(
    String lineId, {
    bool overwrite = false,
    String defaultTime = '08:00-17:00',
  }) async {
    try {
      final lineRow = await DbHelper.queryOne(
        'SELECT * FROM production_lines WHERE line_id = @id',
        params: {'id': lineId},
      );
      if (lineRow == null) return;

      final stationRows = await DbHelper.query(
        'SELECT * FROM production_line_stations WHERE line_id = @id ORDER BY station_no ASC',
        params: {'id': lineId},
      );

      final lineName = lineRow['line_name']?.toString() ?? 'สายการผลิต';
      final newItems = <MachinePlanItem>[];

      int startIndex = overwrite ? 0 : state.plan.items.length;

      for (int i = 0; i < stationRows.length; i++) {
        final s = stationRows[i];
        final mcId = s['machine_id']?.toString() ?? '';
        if (mcId.isEmpty) continue;

        // Fetch machine code from machines table
        final mcRow = await DbHelper.queryOne(
          'SELECT machine_no, machine_name, location FROM machines WHERE machine_id = @mid',
          params: {'mid': mcId},
        );

        final mcNo = mcRow?['machine_no']?.toString() ?? s['machine_name']?.toString() ?? 'MC';
        final mcName = mcRow?['machine_name']?.toString() ?? s['station_name']?.toString() ?? 'เครื่องจักร';
        final location = mcRow?['location']?.toString() ?? '';

        List<String> availableIds = [mcId];
        if (s['secondary_machine_ids'] != null &&
            s['secondary_machine_ids'].toString().isNotEmpty) {
          try {
            final secList = List<String>.from(jsonDecode(s['secondary_machine_ids']));
            availableIds.addAll(secList);
          } catch (_) {}
        }

        final bld = s['building']?.toString() ?? (lineRow['department']?.toString() ?? 'อาคาร 1');
        final rm = s['room']?.toString() ?? location;

        final item = MachinePlanItem(
          itemId: const Uuid().v4(),
          planId: state.plan.planId,
          lineId: lineId,
          lineName: lineName,
          stationId: s['station_id']?.toString(),
          machineId: mcId,
          machineCode: mcNo,
          machineName: mcName,
          building: bld,
          room: rm,
          availableMachineIds: availableIds.toSet().toList(),
          dayMon: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayTue: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayWed: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayThu: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayFri: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          daySat: const DayScheduleSlot(), // default empty on Saturday
          remarks: lineName,
          orderIndex: startIndex + i,
        );

        newItems.add(item);
      }

      if (overwrite) {
        // Delete old items from DB
        await DbHelper.execute(
          'DELETE FROM machine_plan_items WHERE plan_id = @pid',
          params: {'pid': state.plan.planId},
        );
      }

      // Insert new items into DB
      for (final item in newItems) {
        await _insertItemToDb(item);
      }

      final updatedList = overwrite ? newItems : [...state.plan.items, ...newItems];
      state = state.copyWith(
        plan: state.plan.copyWith(items: updatedList),
      );
      VectorDbService.syncMachinePlan(state.plan.planId);
    } catch (_) {}
  }

  Future<void> addMachinesFromRegistry(
    List<Map<String, dynamic>> machineRecords, {
    String? building,
    String? room,
    String defaultTime = '08:00-17:00',
    String? sundayTime,
    String remarks = '',
  }) async {
    try {
      final newItems = <MachinePlanItem>[];
      int startIndex = state.plan.items.length;

      for (int i = 0; i < machineRecords.length; i++) {
        final m = machineRecords[i];
        final mcId = m['machine_id']?.toString() ?? '';
        if (mcId.isEmpty) continue;

        final mcNo = m['machine_no']?.toString() ?? 'MC';
        final mcName = m['machine_name']?.toString() ?? 'เครื่องจักร';
        final dept = m['dept_name']?.toString() ?? '';
        final location = m['location']?.toString() ?? '';

        final bld = (building != null && building.trim().isNotEmpty)
            ? building.trim()
            : (dept.isNotEmpty ? dept : 'อาคาร 1');
        final rm = (room != null && room.trim().isNotEmpty)
            ? room.trim()
            : location;

        final item = MachinePlanItem(
          itemId: const Uuid().v4(),
          planId: state.plan.planId,
          machineId: mcId,
          machineCode: mcNo,
          machineName: mcName,
          building: bld,
          room: rm,
          availableMachineIds: [mcId],
          dayMon: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayTue: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayWed: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayThu: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          dayFri: defaultTime.isNotEmpty ? DayScheduleSlot(time: defaultTime) : const DayScheduleSlot(),
          daySat: const DayScheduleSlot(),
          daySun: (sundayTime != null && sundayTime.isNotEmpty) ? DayScheduleSlot(time: sundayTime) : const DayScheduleSlot(),
          remarks: remarks,
          orderIndex: startIndex + i,
        );

        newItems.add(item);
        await _insertItemToDb(item);
      }

      state = state.copyWith(
        plan: state.plan.copyWith(items: [...state.plan.items, ...newItems]),
      );
      VectorDbService.syncMachinePlan(state.plan.planId);
    } catch (_) {}
  }

  Future<void> updateSlot(String itemId, DayOfWeek day, DayScheduleSlot slot) async {
    final updatedItems = state.plan.items.map((item) {
      if (item.itemId == itemId) {
        return item.withSlot(day, slot);
      }
      return item;
    }).toList();

    state = state.copyWith(
      plan: state.plan.copyWith(items: updatedItems),
    );

    // Save slot to DB
    final colName = _dayToColumn(day);
    await DbHelper.execute('''
      UPDATE machine_plan_items 
      SET $colName = @val, updated_at = CURRENT_TIMESTAMP
      WHERE item_id = @id
    ''', params: {
      'val': jsonEncode(slot.toJson()),
      'id': itemId,
    });
    VectorDbService.syncMachinePlan(state.plan.planId);
  }

  Future<void> updateItemMachine(String itemId, String machineId) async {
    final mcRow = await DbHelper.queryOne(
      'SELECT machine_no, machine_name, location FROM machines WHERE machine_id = @mid',
      params: {'mid': machineId},
    );

    final mcNo = mcRow?['machine_no']?.toString() ?? 'MC';
    final mcName = mcRow?['machine_name']?.toString() ?? 'เครื่องจักร';

    final updatedItems = state.plan.items.map((item) {
      if (item.itemId == itemId) {
        return item.copyWith(
          machineId: machineId,
          machineCode: mcNo,
          machineName: mcName,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(
      plan: state.plan.copyWith(items: updatedItems),
    );

    await DbHelper.execute('''
      UPDATE machine_plan_items
      SET machine_id = @mid, machine_code = @mno, machine_name = @mname, updated_at = CURRENT_TIMESTAMP
      WHERE item_id = @id
    ''', params: {
      'mid': machineId,
      'mno': mcNo,
      'mname': mcName,
      'id': itemId,
    });
    VectorDbService.syncMachinePlan(state.plan.planId);
  }

  Future<void> updateItemDetails(
    String itemId, {
    String? building,
    String? room,
    String? remarks,
  }) async {
    final updatedItems = state.plan.items.map((item) {
      if (item.itemId == itemId) {
        return item.copyWith(
          building: building ?? item.building,
          room: room ?? item.room,
          remarks: remarks ?? item.remarks,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(
      plan: state.plan.copyWith(items: updatedItems),
    );

    await DbHelper.execute('''
      UPDATE machine_plan_items
      SET building = @bld, room = @rm, remarks = @rmk, updated_at = CURRENT_TIMESTAMP
      WHERE item_id = @id
    ''', params: {
      'bld': building,
      'rm': room,
      'rmk': remarks,
      'id': itemId,
    });
    VectorDbService.syncMachinePlan(state.plan.planId);
  }

  Future<void> removeItem(String itemId) async {
    final updatedItems = state.plan.items.where((i) => i.itemId != itemId).toList();
    state = state.copyWith(
      plan: state.plan.copyWith(items: updatedItems),
    );

    await DbHelper.execute(
      'DELETE FROM machine_plan_items WHERE item_id = @id',
      params: {'id': itemId},
    );
    VectorDbService.syncMachinePlan(state.plan.planId);
  }

  Future<void> _insertItemToDb(MachinePlanItem item) async {
    await DbHelper.execute('''
      INSERT INTO machine_plan_items (
        item_id, plan_id, line_id, station_id,
        machine_id, machine_code, machine_name,
        building, room,
        day_mon, day_tue, day_wed, day_thu, day_fri, day_sat, day_sun,
        remarks, order_index, created_at, updated_at
      ) VALUES (
        @item_id, @plan_id, @line_id, @station_id,
        @machine_id, @machine_code, @machine_name,
        @building, @room,
        @day_mon, @day_tue, @day_wed, @day_thu, @day_fri, @day_sat, @day_sun,
        @remarks, @order_index, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
    ''', params: item.toMap());
  }

  String _dayToColumn(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.mon:
        return 'day_mon';
      case DayOfWeek.tue:
        return 'day_tue';
      case DayOfWeek.wed:
        return 'day_wed';
      case DayOfWeek.thu:
        return 'day_thu';
      case DayOfWeek.fri:
        return 'day_fri';
      case DayOfWeek.sat:
        return 'day_sat';
      case DayOfWeek.sun:
        return 'day_sun';
    }
  }
}

final machinePlanningProvider =
    StateNotifierProvider<MachinePlanningNotifier, MachinePlanningState>((ref) {
  return MachinePlanningNotifier();
});
