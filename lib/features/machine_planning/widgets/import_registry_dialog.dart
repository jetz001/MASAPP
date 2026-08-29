import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../machine_intake/machine_provider.dart';
import '../providers/machine_planning_provider.dart';

class ImportRegistryDialog extends ConsumerStatefulWidget {
  const ImportRegistryDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const ImportRegistryDialog(),
    );
  }

  @override
  ConsumerState<ImportRegistryDialog> createState() => _ImportRegistryDialogState();
}

class _ImportRegistryDialogState extends ConsumerState<ImportRegistryDialog> {
  final Set<String> _selectedMachineIds = {};
  String _searchQuery = '';
  String _building = 'อาคาร 1';
  String _room = '';
  String _defaultTime = '08:00-17:00';
  String _sundayTime = '';
  String _remarks = '';
  bool _isLoading = false;

  late final TextEditingController _buildingController;
  late final TextEditingController _roomController;
  late final TextEditingController _timeController;
  late final TextEditingController _sundayTimeController;
  late final TextEditingController _remarksController;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _buildingController = TextEditingController(text: _building);
    _roomController = TextEditingController(text: _room);
    _timeController = TextEditingController(text: _defaultTime);
    _sundayTimeController = TextEditingController(text: _sundayTime);
    _remarksController = TextEditingController(text: _remarks);
    _searchController = TextEditingController(text: _searchQuery);
  }

  @override
  void dispose() {
    _buildingController.dispose();
    _roomController.dispose();
    _timeController.dispose();
    _sundayTimeController.dispose();
    _remarksController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final machinesAsync = ref.watch(machineListProvider(const MachineListFilter()));
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.precision_manufacturing_outlined, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text(
            'ดึงเครื่องจักรจากทะเบียน (Machine Registry)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 520,
        child: machinesAsync.when(
          data: (machines) {
            final filteredMachines = machines.where((m) {
              if (_searchQuery.trim().isEmpty) return true;
              final q = _searchQuery.toLowerCase().trim();
              return m.machineNo.toLowerCase().contains(q) ||
                  (m.machineName != null && m.machineName!.toLowerCase().contains(q)) ||
                  (m.brand != null && m.brand!.toLowerCase().contains(q)) ||
                  (m.deptName != null && m.deptName!.toLowerCase().contains(q)) ||
                  (m.location != null && m.location!.toLowerCase().contains(q));
            }).toList();

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Machine List with search and multi-select
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      // Search bar
                      SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'ค้นหาชื่อ, รหัส, แผนก, สถานที่...',
                            prefixIcon: const Icon(Icons.search, size: 16),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 14),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            isDense: true,
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Select All / Deselect All Bar
                      Row(
                        children: [
                          Text(
                            'เลือกแล้ว ${_selectedMachineIds.length} จาก ${filteredMachines.length} เครื่อง',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setState(() {
                                for (final m in filteredMachines) {
                                  if (m.machineId != null) {
                                    _selectedMachineIds.add(m.machineId!);
                                  }
                                }
                              });
                            },
                            child: const Text('เลือกทั้งหมด', style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setState(() => _selectedMachineIds.clear());
                            },
                            child: const Text('ล้างที่เลือก', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Machine List
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: filteredMachines.isEmpty
                              ? const Center(
                                  child: Text('ไม่พบเครื่องจักรที่ตรงกับเงื่อนไข', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                )
                              : Material(
                                  color: Colors.transparent,
                                  child: ListView.separated(
                                    itemCount: filteredMachines.length,
                                    separatorBuilder: (ctx, idx) => const Divider(height: 1),
                                    itemBuilder: (ctx, i) {
                                      final m = filteredMachines[i];
                                      final mid = m.machineId ?? '';
                                      final isSelected = _selectedMachineIds.contains(mid);

                                      return CheckboxListTile(
                                        value: isSelected,
                                        dense: true,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                        title: Text(
                                          '[${m.machineNo}] ${m.machineName ?? ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          'แผนก: ${m.deptName ?? '-'} | สถานที่: ${m.location ?? '-'}',
                                          style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedMachineIds.add(mid);
                                            } else {
                                              _selectedMachineIds.remove(mid);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Right Column: Configuration Form (Building, Room, Default Times, Remarks)
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚙️ กำหนดค่าเริ่มต้นสำหรับรายการที่เลือก:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),

                        // Building Input
                        TextField(
                          controller: _buildingController,
                          decoration: const InputDecoration(
                            labelText: 'อาคาร (Building)',
                            hintText: 'เช่น อาคาร 1, อาคาร 2',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.apartment_rounded, size: 16),
                            isDense: true,
                          ),
                          onChanged: (val) => _building = val,
                        ),
                        const SizedBox(height: 10),

                        // Room Input
                        TextField(
                          controller: _roomController,
                          decoration: const InputDecoration(
                            labelText: 'ห้อง (Room)',
                            hintText: 'เช่น ห้องอัดแคปซูล 1',
                            helperText: 'หากเว้นว่าง จะใช้ Location จากทะเบียน',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.meeting_room_outlined, size: 16),
                            isDense: true,
                          ),
                          onChanged: (val) => _room = val,
                        ),
                        const SizedBox(height: 10),

                        // Default Weekday Time Slot
                        TextField(
                          controller: _timeController,
                          decoration: const InputDecoration(
                            labelText: 'เวลาทำงาน จันทร์ - ศุกร์',
                            hintText: '08:00-17:00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.timer_outlined, size: 16),
                            isDense: true,
                          ),
                          onChanged: (val) => _defaultTime = val,
                        ),
                        const SizedBox(height: 10),

                        // Default Sunday Time Slot
                        TextField(
                          controller: _sundayTimeController,
                          decoration: const InputDecoration(
                            labelText: 'เวลาทำงาน วันอาทิตย์ (ถ้ามี)',
                            hintText: 'เว้นว่างหากเป็นวันหยุด',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.wb_sunny_outlined, size: 16, color: Colors.redAccent),
                            isDense: true,
                          ),
                          onChanged: (val) => _sundayTime = val,
                        ),
                        const SizedBox(height: 10),

                        // Remarks Input
                        TextField(
                          controller: _remarksController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'หมายเหตุ / สูตรสินค้า',
                            hintText: 'เช่น ผลิตยาธาตุ 4 ตรากิเลน',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (val) => _remarks = val,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.add_task_rounded, size: 18),
          label: Text('เพิ่ม ${_selectedMachineIds.length} เครื่องลงตาราง'),
          onPressed: (_selectedMachineIds.isEmpty || _isLoading)
              ? null
              : () async {
                  setState(() => _isLoading = true);
                  final machines = ref.read(machineListProvider(const MachineListFilter())).value ?? [];
                  final selectedList = machines
                      .where((m) => _selectedMachineIds.contains(m.machineId))
                      .map((m) => {
                            'machine_id': m.machineId,
                            'machine_no': m.machineNo,
                            'machine_name': m.machineName,
                            'dept_name': m.deptName,
                            'location': m.location,
                          })
                      .toList();

                  await ref.read(machinePlanningProvider.notifier).addMachinesFromRegistry(
                        selectedList,
                        building: _buildingController.text.trim(),
                        room: _roomController.text.trim().isNotEmpty ? _roomController.text.trim() : null,
                        defaultTime: _timeController.text.trim(),
                        sundayTime: _sundayTimeController.text.trim().isNotEmpty ? _sundayTimeController.text.trim() : null,
                        remarks: _remarksController.text.trim(),
                      );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('เพิ่ม ${selectedList.length} เครื่องลงตารางเรียบร้อยแล้ว'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  }
                },
        ),
      ],
    );
  }
}
