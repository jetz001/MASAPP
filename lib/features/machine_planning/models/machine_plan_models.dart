import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum DayOfWeek {
  mon,
  tue,
  wed,
  thu,
  fri,
  sat,
  sun;

  String get labelTh {
    switch (this) {
      case DayOfWeek.mon:
        return 'จันทร์';
      case DayOfWeek.tue:
        return 'อังคาร';
      case DayOfWeek.wed:
        return 'พุธ';
      case DayOfWeek.thu:
        return 'พฤหัสบดี';
      case DayOfWeek.fri:
        return 'ศุกร์';
      case DayOfWeek.sat:
        return 'เสาร์';
      case DayOfWeek.sun:
        return 'อาทิตย์';
    }
  }

  Color get headerColor {
    switch (this) {
      case DayOfWeek.mon:
        return const Color(0xFFFFD54F); // Yellow
      case DayOfWeek.tue:
        return const Color(0xFFF48FB1); // Pink
      case DayOfWeek.wed:
        return const Color(0xFF81C784); // Green
      case DayOfWeek.thu:
        return const Color(0xFFFFB74D); // Orange
      case DayOfWeek.fri:
        return const Color(0xFF64B5F6); // Blue
      case DayOfWeek.sat:
        return const Color(0xFFBA68C8); // Purple
      case DayOfWeek.sun:
        return const Color(0xFFE57373); // Red
    }
  }

  Color get headerTextColor {
    switch (this) {
      case DayOfWeek.mon:
      case DayOfWeek.wed:
      case DayOfWeek.thu:
        return Colors.black87;
      default:
        return Colors.white;
    }
  }
}

class DayScheduleSlot {
  final String time; // e.g. '08:00-17:00' or empty
  final bool isOt; // true if OT
  final String? colorKey; // 'yellow', 'orange', 'green', 'blue', 'purple', etc.
  final String? customLabel;

  const DayScheduleSlot({
    this.time = '',
    this.isOt = false,
    this.colorKey,
    this.customLabel,
  });

  bool get isEmpty => time.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
        'time': time,
        'is_ot': isOt,
        'color': colorKey,
        'label': customLabel,
      };

  factory DayScheduleSlot.fromJson(dynamic json) {
    if (json == null) return const DayScheduleSlot();
    if (json is String) {
      if (json.trim().isEmpty) return const DayScheduleSlot();
      try {
        final map = jsonDecode(json);
        if (map is Map<String, dynamic>) {
          return DayScheduleSlot(
            time: map['time']?.toString() ?? '',
            isOt: map['is_ot'] == true,
            colorKey: map['color']?.toString(),
            customLabel: map['label']?.toString(),
          );
        }
      } catch (_) {
        // Plain string fallback
        final isOt = json.toUpperCase().contains('OT');
        return DayScheduleSlot(time: json, isOt: isOt);
      }
    } else if (json is Map) {
      return DayScheduleSlot(
        time: json['time']?.toString() ?? '',
        isOt: json['is_ot'] == true,
        colorKey: mapKey(json['color']),
        customLabel: json['label']?.toString(),
      );
    }
    return const DayScheduleSlot();
  }

  static String? mapKey(dynamic val) => val?.toString();

  DayScheduleSlot copyWith({
    String? time,
    bool? isOt,
    String? colorKey,
    String? customLabel,
  }) {
    return DayScheduleSlot(
      time: time ?? this.time,
      isOt: isOt ?? this.isOt,
      colorKey: colorKey ?? this.colorKey,
      customLabel: customLabel ?? this.customLabel,
    );
  }

  Color get displayBgColor {
    if (isEmpty) return Colors.transparent;
    if (isOt) return const Color(0xFFFFCC80); // Orange highlight for OT
    if (colorKey == 'yellow') return const Color(0xFFFFF59D);
    if (colorKey == 'green') return const Color(0xFFA5D6A7);
    if (colorKey == 'blue') return const Color(0xFF90CAF9);
    if (colorKey == 'purple') return const Color(0xFFCE93D8);
    if (colorKey == 'red') return const Color(0xFFFFCDD2);
    return const Color(0xFFFFF9C4); // Light yellow default
  }
}

class MachinePlanItem {
  final String itemId;
  final String planId;
  final String? lineId;
  final String? lineName;
  final String? stationId;
  final String machineId;
  final String machineCode;
  final String machineName;
  final String? building; // e.g. 'อาคาร 1', 'อาคาร 2'
  final String? room; // e.g. 'ห้องอัดแคปซูล 1'
  final List<String> availableMachineIds; // Primary + Backup candidates

  final DayScheduleSlot dayMon;
  final DayScheduleSlot dayTue;
  final DayScheduleSlot dayWed;
  final DayScheduleSlot dayThu;
  final DayScheduleSlot dayFri;
  final DayScheduleSlot daySat;
  final DayScheduleSlot daySun;

  final String remarks; // e.g. 'ผลิตยาธาตุ 4 ตรากิเลน -180ml', 'น๊อตpre roller ถูหัวสากล่าง'
  final int orderIndex;

  const MachinePlanItem({
    required this.itemId,
    required this.planId,
    this.lineId,
    this.lineName,
    this.stationId,
    required this.machineId,
    required this.machineCode,
    required this.machineName,
    this.building,
    this.room,
    this.availableMachineIds = const [],
    this.dayMon = const DayScheduleSlot(),
    this.dayTue = const DayScheduleSlot(),
    this.dayWed = const DayScheduleSlot(),
    this.dayThu = const DayScheduleSlot(),
    this.dayFri = const DayScheduleSlot(),
    this.daySat = const DayScheduleSlot(),
    this.daySun = const DayScheduleSlot(),
    this.remarks = '',
    this.orderIndex = 0,
  });

  DayScheduleSlot getSlot(DayOfWeek day) {
    switch (day) {
      case DayOfWeek.mon:
        return dayMon;
      case DayOfWeek.tue:
        return dayTue;
      case DayOfWeek.wed:
        return dayWed;
      case DayOfWeek.thu:
        return dayThu;
      case DayOfWeek.fri:
        return dayFri;
      case DayOfWeek.sat:
        return daySat;
      case DayOfWeek.sun:
        return daySun;
    }
  }

  MachinePlanItem withSlot(DayOfWeek day, DayScheduleSlot slot) {
    switch (day) {
      case DayOfWeek.mon:
        return copyWith(dayMon: slot);
      case DayOfWeek.tue:
        return copyWith(dayTue: slot);
      case DayOfWeek.wed:
        return copyWith(dayWed: slot);
      case DayOfWeek.thu:
        return copyWith(dayThu: slot);
      case DayOfWeek.fri:
        return copyWith(dayFri: slot);
      case DayOfWeek.sat:
        return copyWith(daySat: slot);
      case DayOfWeek.sun:
        return copyWith(daySun: slot);
    }
  }

  MachinePlanItem copyWith({
    String? lineId,
    String? lineName,
    String? stationId,
    String? machineId,
    String? machineCode,
    String? machineName,
    String? building,
    String? room,
    List<String>? availableMachineIds,
    DayScheduleSlot? dayMon,
    DayScheduleSlot? dayTue,
    DayScheduleSlot? dayWed,
    DayScheduleSlot? dayThu,
    DayScheduleSlot? dayFri,
    DayScheduleSlot? daySat,
    DayScheduleSlot? daySun,
    String? remarks,
    int? orderIndex,
  }) {
    return MachinePlanItem(
      itemId: itemId,
      planId: planId,
      lineId: lineId ?? this.lineId,
      lineName: lineName ?? this.lineName,
      stationId: stationId ?? this.stationId,
      machineId: machineId ?? this.machineId,
      machineCode: machineCode ?? this.machineCode,
      machineName: machineName ?? this.machineName,
      building: building ?? this.building,
      room: room ?? this.room,
      availableMachineIds: availableMachineIds ?? this.availableMachineIds,
      dayMon: dayMon ?? this.dayMon,
      dayTue: dayTue ?? this.dayTue,
      dayWed: dayWed ?? this.dayWed,
      dayThu: dayThu ?? this.dayThu,
      dayFri: dayFri ?? this.dayFri,
      daySat: daySat ?? this.daySat,
      daySun: daySun ?? this.daySun,
      remarks: remarks ?? this.remarks,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'plan_id': planId,
        'line_id': lineId,
        'station_id': stationId,
        'machine_id': machineId,
        'machine_code': machineCode,
        'machine_name': machineName,
        'building': building,
        'room': room,
        'day_mon': jsonEncode(dayMon.toJson()),
        'day_tue': jsonEncode(dayTue.toJson()),
        'day_wed': jsonEncode(dayWed.toJson()),
        'day_thu': jsonEncode(dayThu.toJson()),
        'day_fri': jsonEncode(dayFri.toJson()),
        'day_sat': jsonEncode(daySat.toJson()),
        'day_sun': jsonEncode(daySun.toJson()),
        'remarks': remarks,
        'order_index': orderIndex,
      };

  factory MachinePlanItem.fromMap(Map<String, dynamic> map, {List<String> availableIds = const []}) {
    return MachinePlanItem(
      itemId: map['item_id'].toString(),
      planId: map['plan_id'].toString(),
      lineId: map['line_id']?.toString(),
      lineName: map['line_name']?.toString(),
      stationId: map['station_id']?.toString(),
      machineId: map['machine_id']?.toString() ?? '',
      machineCode: map['machine_code']?.toString() ?? '',
      machineName: map['machine_name']?.toString() ?? '',
      building: map['building']?.toString(),
      room: map['room']?.toString(),
      availableMachineIds: availableIds.isNotEmpty ? availableIds : [if (map['machine_id'] != null) map['machine_id'].toString()],
      dayMon: DayScheduleSlot.fromJson(map['day_mon']),
      dayTue: DayScheduleSlot.fromJson(map['day_tue']),
      dayWed: DayScheduleSlot.fromJson(map['day_wed']),
      dayThu: DayScheduleSlot.fromJson(map['day_thu']),
      dayFri: DayScheduleSlot.fromJson(map['day_fri']),
      daySat: DayScheduleSlot.fromJson(map['day_sat']),
      daySun: DayScheduleSlot.fromJson(map['day_sun']),
      remarks: map['remarks']?.toString() ?? '',
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
    );
  }
}

class MachineWeeklyPlan {
  final String planId;
  final DateTime weekStartDate; // Monday
  final DateTime weekEndDate; // Saturday / Sunday
  final String title;
  final String? note;
  final List<MachinePlanItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MachineWeeklyPlan({
    required this.planId,
    required this.weekStartDate,
    required this.weekEndDate,
    required this.title,
    this.note,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  String get formattedRange {
    final startFmt = DateFormat('dd/MM').format(weekStartDate);
    final endFmt = DateFormat('dd/MM/yy').format(weekEndDate);
    return '$startFmt - $endFmt';
  }

  int get weekNumber {
    final dayOfYear = int.parse(DateFormat('D').format(weekStartDate));
    return ((dayOfYear - weekStartDate.weekday + 10) / 7).floor();
  }

  Map<String, dynamic> toMap() => {
        'plan_id': planId,
        'week_start_date': DateFormat('yyyy-MM-dd').format(weekStartDate),
        'week_end_date': DateFormat('yyyy-MM-dd').format(weekEndDate),
        'title': title,
        'note': note,
      };

  MachineWeeklyPlan copyWith({
    String? title,
    String? note,
    List<MachinePlanItem>? items,
  }) {
    return MachineWeeklyPlan(
      planId: planId,
      weekStartDate: weekStartDate,
      weekEndDate: weekEndDate,
      title: title ?? this.title,
      note: note ?? this.note,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Common Quick Time Presets
class SchedulePreset {
  final String label;
  final String time;
  final bool isOt;
  final String colorKey;

  const SchedulePreset({
    required this.label,
    required this.time,
    this.isOt = false,
    this.colorKey = 'yellow',
  });
}

const List<SchedulePreset> kStandardPresets = [
  SchedulePreset(label: '08:00-17:00 (ปกติ)', time: '08:00-17:00', isOt: false, colorKey: 'yellow'),
  SchedulePreset(label: 'OT 08:00-21:30', time: '08:00-21:30', isOt: true, colorKey: 'orange'),
  SchedulePreset(label: 'OT 08:00-19:00', time: '08:00-19:00', isOt: true, colorKey: 'orange'),
  SchedulePreset(label: 'OT 10:00-19:00', time: '10:00-19:00', isOt: true, colorKey: 'orange'),
  SchedulePreset(label: 'OT 15:00-21:30', time: '15:00-21:30', isOt: true, colorKey: 'orange'),
  SchedulePreset(label: '08:00-12:00 (ครึ่งวันเช้า)', time: '08:00-12:00', isOt: false, colorKey: 'green'),
  SchedulePreset(label: '13:00-17:00 (ครึ่งวันบ่าย)', time: '13:00-17:00', isOt: false, colorKey: 'green'),
  SchedulePreset(label: '09:00-16:00', time: '09:00-16:00', isOt: false, colorKey: 'blue'),
  SchedulePreset(label: '09:30-12:00', time: '09:30-12:00', isOt: false, colorKey: 'blue'),
  SchedulePreset(label: '08:30-17:00', time: '08:30-17:00', isOt: false, colorKey: 'yellow'),
  SchedulePreset(label: '08:30-14:00', time: '08:30-14:00', isOt: false, colorKey: 'blue'),
];
