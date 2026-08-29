import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/machine_plan_models.dart';
import '../providers/machine_planning_provider.dart';
import '../services/machine_plan_excel_service.dart';
import '../services/machine_plan_pdf_service.dart';
import '../widgets/import_line_dialog.dart';
import '../widgets/import_registry_dialog.dart';
import '../widgets/slot_editor_dialog.dart';

class MachinePlanningScreen extends ConsumerStatefulWidget {
  const MachinePlanningScreen({super.key});

  @override
  ConsumerState<MachinePlanningScreen> createState() => _MachinePlanningScreenState();
}

class _MachinePlanningScreenState extends ConsumerState<MachinePlanningScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(machinePlanningProvider);
    final notifier = ref.read(machinePlanningProvider.notifier);
    final theme = Theme.of(context);

    final days = [
      DayOfWeek.mon,
      DayOfWeek.tue,
      DayOfWeek.wed,
      DayOfWeek.thu,
      DayOfWeek.fri,
      DayOfWeek.sat,
      DayOfWeek.sun,
    ];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.calendar_month_outlined, color: Colors.blueAccent, size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'แผนการใช้เครื่องจักร (Machine Planning)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Button: Import from Line Balancing
          Tooltip(
            message: 'ดึงเครื่องจักรจาก Line Balancing',
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.account_tree_outlined, size: 15),
              label: const Text('Line Balancing', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal.shade900,
              ),
              onPressed: () => ImportLineDialog.show(context),
            ),
          ),
          const SizedBox(width: 6),

          // Button: Import from Machine Registry
          Tooltip(
            message: 'ดึงเครื่องจักรจากทะเบียนเครื่องจักร',
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.precision_manufacturing_outlined, size: 15),
              label: const Text('ทะเบียนเครื่องจักร', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue.shade900,
              ),
              onPressed: () => ImportRegistryDialog.show(context),
            ),
          ),
          const SizedBox(width: 6),

          // Button: Export PDF
          Tooltip(
            message: 'ส่งออกรายงาน PDF',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 15, color: Colors.red),
              label: const Text('PDF', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: state.plan.items.isEmpty
                  ? null
                  : () async {
                      try {
                        await MachinePlanPdfService.generateAndOpen(
                          plan: state.plan,
                          buildingFilter: state.selectedBuilding,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้าง PDF: $e')),
                          );
                        }
                      }
                    },
            ),
          ),
          const SizedBox(width: 6),

          // Button: Export Excel
          Tooltip(
            message: 'ส่งออกไฟล์ Excel (.xlsx)',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.table_chart_outlined, size: 15, color: Colors.green),
              label: const Text('Excel', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: state.plan.items.isEmpty
                  ? null
                  : () async {
                      try {
                        await MachinePlanExcelService.generateAndOpen(
                          plan: state.plan,
                          buildingFilter: state.selectedBuilding,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้าง Excel: $e')),
                          );
                        }
                      }
                    },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Top Control & Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Week Selector & Info
                Row(
                  children: [
                    // Week Navigator Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, size: 20),
                            tooltip: 'สัปดาห์ก่อนหน้า',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: notifier.prevWeek,
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: state.plan.weekStartDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2040),
                              );
                              if (picked != null) {
                                notifier.loadPlanForWeek(picked);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 13, color: Colors.blueAccent),
                                  const SizedBox(width: 6),
                                  Text(
                                    'สัปดาห์ ${DateFormat('dd/MM/yyyy').format(state.plan.weekStartDate)} - ${DateFormat('dd/MM/yyyy').format(state.plan.weekEndDate)} (W${state.plan.weekNumber})',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, size: 20),
                            tooltip: 'สัปดาห์ถัดไป',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: notifier.nextWeek,
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Count Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        '${state.filteredItems.length} รายการ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Bottom Row: Filters & Search
                Row(
                  children: [
                    // Filter: Building
                    const Icon(Icons.apartment_rounded, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    const Text('อาคาร:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state.availableBuildings.contains(state.selectedBuilding)
                              ? state.selectedBuilding
                              : 'ทั้งหมด',
                          isDense: true,
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                          items: state.availableBuildings.map((b) {
                            return DropdownMenuItem<String>(
                              value: b,
                              child: Text(b == 'ทั้งหมด' ? '🏢 ทุกอาคาร' : '📍 $b'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) notifier.setBuildingFilter(val);
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Filter: Room
                    const Icon(Icons.meeting_room_outlined, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    const Text('ห้อง:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state.availableRooms.contains(state.selectedRoom)
                              ? state.selectedRoom
                              : 'ทั้งหมด',
                          isDense: true,
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                          items: state.availableRooms.map((r) {
                            return DropdownMenuItem<String>(
                              value: r,
                              child: Text(r == 'ทั้งหมด' ? '🚪 ทุกห้อง' : r),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) notifier.setRoomFilter(val);
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Search Bar
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'ค้นหาชื่อเครื่องจักร / รหัส / สินค้า / หมายเหตุ...',
                            prefixIcon: const Icon(Icons.search, size: 16),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 14),
                                    onPressed: () {
                                      _searchController.clear();
                                      notifier.setSearchQuery('');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            isDense: true,
                          ),
                          onChanged: notifier.setSearchQuery,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Master Table Area
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.filteredItems.isEmpty
                    ? _buildEmptyState(context, state)
                    : _buildMasterTable(context, state, notifier, days),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, MachinePlanningState state) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_view_week_rounded, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            state.plan.items.isEmpty
                ? 'ยังไม่มีรายการเครื่องจักรในสัปดาห์นี้'
                : 'ไม่พบรายการที่ตรงกับเงื่อนไขการค้นหา',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (state.plan.items.isEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('ดึงเครื่องจักรจาก Line Balancing'),
                  onPressed: () => ImportLineDialog.show(context),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.precision_manufacturing_outlined),
                  label: const Text('ดึงจากทะเบียนเครื่องจักร'),
                  onPressed: () => ImportRegistryDialog.show(context),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMasterTable(
    BuildContext context,
    MachinePlanningState state,
    MachinePlanningNotifier notifier,
    List<DayOfWeek> days,
  ) {
    final items = state.filteredItems;

    // Group filtered items by building for table section headers
    final Map<String, List<MachinePlanItem>> buildingGroups = {};
    for (final item in items) {
      final bld = (item.building != null && item.building!.trim().isNotEmpty)
          ? item.building!.trim()
          : 'ส่วนกลาง / อื่นๆ';
      buildingGroups.putIfAbsent(bld, () => []).add(item);
    }

    return Scrollbar(
      controller: _verticalScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _verticalScrollController,
        scrollDirection: Axis.vertical,
        child: Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final bldEntry in buildingGroups.entries) ...[
                    _buildBuildingSection(
                      context,
                      bldEntry.key,
                      bldEntry.value,
                      notifier,
                      days,
                      state.plan.weekStartDate,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBuildingSection(
    BuildContext context,
    String buildingName,
    List<MachinePlanItem> items,
    MachinePlanningNotifier notifier,
    List<DayOfWeek> days,
    DateTime weekStartDate,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black87, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Building Section Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              border: const Border(bottom: BorderSide(color: Colors.black26, width: 1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.apartment_rounded, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 6),
                Text(
                  buildingName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${items.length} รายการ)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
            dataRowMinHeight: 46,
            dataRowMaxHeight: 54,
            columnSpacing: 8,
            horizontalMargin: 6,
            border: const TableBorder(
              horizontalInside: BorderSide(color: Colors.black45, width: 0.6),
              verticalInside: BorderSide(color: Colors.black45, width: 0.6),
            ),
            columns: [
              // ลำดับ
              const DataColumn(
                label: SizedBox(
                  width: 32,
                  child: Center(
                    child: Text(
                      'ลำดับ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                ),
              ),
              // อาคาร
              const DataColumn(
                label: SizedBox(
                  width: 75,
                  child: Text(
                    'อาคาร',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
              ),
              // เครื่องจักร
              const DataColumn(
                label: SizedBox(
                  width: 165,
                  child: Text(
                    'เครื่องจักร',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
              ),
              // Days Mon - Sun
              ...days.map((day) {
                final dayOffset = days.indexOf(day);
                final dayDate = weekStartDate.add(Duration(days: dayOffset));
                final beYear = ((dayDate.year + 543) % 100).toString().padLeft(2, '0');
                final dateLabel = '${DateFormat('dd/MM').format(dayDate)}/$beYear';

                return DataColumn(
                  label: SizedBox(
                    width: 80,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 1),
                      decoration: BoxDecoration(
                        color: day.headerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            day.labelTh,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: day.headerTextColor,
                            ),
                          ),
                          Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 8.5,
                              color: day.headerTextColor.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              // ห้อง
              const DataColumn(
                label: SizedBox(
                  width: 80,
                  child: Text(
                    'ห้อง',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
              ),
              // หมายเหตุ
              const DataColumn(
                label: SizedBox(
                  width: 130,
                  child: Text(
                    'หมายเหตุ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.red),
                  ),
                ),
              ),
              // Action
              const DataColumn(
                label: SizedBox(
                  width: 38,
                  child: Center(
                    child: Text(
                      'จัดการ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                ),
              ),
            ],
            rows: items.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final item = entry.value;

              return DataRow(
                cells: [
                  // No
                  DataCell(
                    SizedBox(
                      width: 32,
                      child: Center(
                        child: Text(
                          '$index',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                    ),
                  ),
                  // Building Cell (Editable)
                  DataCell(
                    SizedBox(
                      width: 75,
                      child: InkWell(
                        onTap: () => _editBuildingDialog(context, item, notifier),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.building?.isNotEmpty == true ? item.building! : buildingName,
                                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.edit, size: 10, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Machine Code & Name with Backup switcher
                  DataCell(
                    SizedBox(
                      width: 165,
                      child: _buildMachineCell(context, item, notifier),
                    ),
                  ),
                  // Mon - Sun cells
                  ...days.map((day) => _buildDayCell(context, item, day, notifier)),
                  // Room Cell
                  DataCell(
                    SizedBox(
                      width: 80,
                      child: InkWell(
                        onTap: () => _editRoomDialog(context, item, notifier),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.room?.isNotEmpty == true ? item.room! : 'ระบุห้อง...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: item.room?.isNotEmpty == true
                                        ? Colors.black87
                                        : Colors.grey.shade400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.edit, size: 10, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Remarks Cell
                  DataCell(
                    SizedBox(
                      width: 130,
                      child: InkWell(
                        onTap: () => _editRemarksDialog(context, item, notifier),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.remarks.isNotEmpty ? item.remarks : 'เพิ่มหมายเหตุ...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: item.remarks.contains('**')
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: item.remarks.contains('**')
                                        ? Colors.red.shade800
                                        : (item.remarks.isNotEmpty
                                            ? Colors.black87
                                            : Colors.grey.shade400),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.edit, size: 10, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Action (Delete)
                  DataCell(
                    SizedBox(
                      width: 38,
                      child: Center(
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          tooltip: 'ลบออกจากตารางสัปดาห์นี้',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmDeleteItem(context, item, notifier),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineCell(
    BuildContext context,
    MachinePlanItem item,
    MachinePlanningNotifier notifier,
  ) {
    // Check if item has backup machines
    final hasBackups = item.availableMachineIds.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.machineName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasBackups)
              PopupMenuButton<String>(
                icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.orange),
                tooltip: 'สลับเครื่องจักรหลัก / เครื่องจักรรอง',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                itemBuilder: (ctx) {
                  return item.availableMachineIds.map((mid) {
                    final isCurrent = mid == item.machineId;
                    return PopupMenuItem<String>(
                      value: mid,
                      child: Row(
                        children: [
                          Icon(
                            isCurrent ? Icons.check_circle : Icons.circle_outlined,
                            size: 16,
                            color: isCurrent ? Colors.teal : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            mid == item.availableMachineIds.first
                                ? 'เครื่องหลัก ($mid)'
                                : 'เครื่องรอง ($mid)',
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
                onSelected: (newMid) {
                  notifier.updateItemMachine(item.itemId, newMid);
                },
              ),
          ],
        ),
        if (item.machineCode.isNotEmpty)
          Text(
            item.machineCode,
            style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  DataCell _buildDayCell(
    BuildContext context,
    MachinePlanItem item,
    DayOfWeek day,
    MachinePlanningNotifier notifier,
  ) {
    final slot = item.getSlot(day);
    final isOt = slot.isOt;
    final isEmpty = slot.isEmpty;

    return DataCell(
      InkWell(
        onTap: () async {
          final updatedSlot = await SlotEditorDialog.show(
            context,
            machineName: item.machineName,
            dayLabel: day.labelTh,
            initialSlot: slot,
          );
          if (updatedSlot != null) {
            notifier.updateSlot(item.itemId, day, updatedSlot);
          }
        },
        child: Container(
          width: 80,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: slot.displayBgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: isEmpty
              ? Icon(Icons.add, size: 14, color: Colors.grey.shade400)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isOt)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'OT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Text(
                      slot.time,
                      style: TextStyle(
                        fontSize: isOt ? 10 : 10.5,
                        fontWeight: isOt ? FontWeight.bold : FontWeight.normal,
                        color: isOt ? Colors.red.shade900 : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _editBuildingDialog(
    BuildContext context,
    MachinePlanItem item,
    MachinePlanningNotifier notifier,
  ) {
    final controller = TextEditingController(text: item.building ?? '');
    final presets = ['อาคาร 1', 'อาคาร 2', 'อาคาร 4', 'อาคาร 5', 'อาคาร 6'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.apartment_rounded, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('แก้ไขอาคาร (Building)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('เลือกอาคารด่วน:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: presets.map((p) {
                      final isSel = controller.text.trim() == p;
                      return ChoiceChip(
                        label: Text(p, style: const TextStyle(fontSize: 11)),
                        selected: isSel,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => controller.text = p);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'ระบุชื่ออาคาร',
                      hintText: 'เช่น อาคาร 1, อาคาร 2',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
              FilledButton(
                onPressed: () {
                  notifier.updateItemDetails(item.itemId, building: controller.text.trim());
                  Navigator.pop(ctx);
                },
                child: const Text('บันทึก'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editRoomDialog(
    BuildContext context,
    MachinePlanItem item,
    MachinePlanningNotifier notifier,
  ) {
    final controller = TextEditingController(text: item.room ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขห้อง / สถานที่', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ห้อง (Room)',
            hintText: 'เช่น ห้องอัดแคปซูล 1, ห้องหีบห่อ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              notifier.updateItemDetails(item.itemId, room: controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _editRemarksDialog(
    BuildContext context,
    MachinePlanItem item,
    MachinePlanningNotifier notifier,
  ) {
    final controller = TextEditingController(text: item.remarks);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขหมายเหตุ / สินค้า', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'หมายเหตุ (Remarks)',
                  hintText: 'เช่น ผลิตยาธาตุ 4 ตรากิเลน -180ml หรือ **อาการชำรุด**',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '💡 ทิป: ใส่เครื่องหมาย **ข้อความ** เพื่อทำตัวหนาสีแดงในเอกสาร PDF',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              notifier.updateItemDetails(item.itemId, remarks: controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteItem(
    BuildContext context,
    MachinePlanItem item,
    MachinePlanningNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ', style: TextStyle(fontSize: 15)),
        content: Text('ต้องการลบเครื่องจักร "${item.machineName}" ออกจากตารางสัปดาห์นี้หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              notifier.removeItem(item.itemId);
              Navigator.pop(ctx);
            },
            child: const Text('ลบรายการ'),
          ),
        ],
      ),
    );
  }
}
