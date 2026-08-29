import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'line_balancing_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../work_processes/providers/work_process_provider.dart';

class AddStationDialog extends ConsumerStatefulWidget {
  final LineBalancingNotifier notifier;
  final WorkstationData? initialStation;
  final String? fromStationId;
  final Offset? suggestedPosition;

  const AddStationDialog({
    super.key,
    required this.notifier,
    this.initialStation,
    this.fromStationId,
    this.suggestedPosition,
  });

  @override
  ConsumerState<AddStationDialog> createState() => _AddStationDialogState();
}

class _AddStationDialogState extends ConsumerState<AddStationDialog> {
  String name = 'Station';
  double cycleTime = 20.0;
  int workers = 1;
  String? selectedMachineId;
  String? selectedMachineName;
  String? selectedMachineNo;
  List<String> secondaryMachineIds = [];
  int selectedMachineStepCount = 0;
  String? selectedSopTitle;
  bool isCalculating = false;

  double laborCost = 300.0;
  double energyCost = 0.0;
  double materialCost = 0.0;
  double otherCost = 0.0;
  double waitingTimeSec = 0.0;
  int bufferQuantity = 0;

  late final TextEditingController _cycleTimeController;
  late final TextEditingController _nameController;
  late final TextEditingController _workersController;
  late final TextEditingController _buildingController;
  late final TextEditingController _roomController;
  
  late final TextEditingController _laborCostController;
  late final TextEditingController _energyCostController;
  late final TextEditingController _materialCostController;
  late final TextEditingController _otherCostController;

  @override
  void initState() {
    super.initState();
    final s = widget.initialStation;
    if (s != null) {
      name = s.name;
      cycleTime = s.cycleTime;
      workers = s.workers;
      selectedMachineId = s.machineId;
      selectedMachineName = s.machineName;
      secondaryMachineIds = List.from(s.secondaryMachineIds);
      laborCost = s.laborCost;
      energyCost = s.energyCost;
      materialCost = s.materialCost;
      otherCost = s.otherCost;
      waitingTimeSec = s.waitingTimeSec;
      bufferQuantity = s.bufferQuantity;

      _nameController = TextEditingController(text: s.name);
      _cycleTimeController = TextEditingController(text: s.cycleTime.toStringAsFixed(2));
      _workersController = TextEditingController(text: s.workers.toString());
      _buildingController = TextEditingController(text: s.building ?? '');
      _roomController = TextEditingController(text: s.room ?? '');
      _laborCostController = TextEditingController(text: s.laborCost.toStringAsFixed(2));
      _energyCostController = TextEditingController(text: s.energyCost.toStringAsFixed(2));
      _materialCostController = TextEditingController(text: s.materialCost.toStringAsFixed(2));
      _otherCostController = TextEditingController(text: s.otherCost.toStringAsFixed(2));
    } else {
      _nameController = TextEditingController(text: 'Station');
      _cycleTimeController = TextEditingController(text: '20.0');
      _workersController = TextEditingController(text: '1');
      _buildingController = TextEditingController();
      _roomController = TextEditingController();
      _laborCostController = TextEditingController(text: '300.0');
      _energyCostController = TextEditingController(text: '0.0');
      _materialCostController = TextEditingController(text: '0.0');
      _otherCostController = TextEditingController(text: '0.0');
    }
  }

  @override
  void dispose() {
    _cycleTimeController.dispose();
    _nameController.dispose();
    _workersController.dispose();
    _buildingController.dispose();
    _roomController.dispose();
    _laborCostController.dispose();
    _energyCostController.dispose();
    _materialCostController.dispose();
    _otherCostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final machinesAsync = ref.watch(machineListProvider(const MachineListFilter()));
    final workProcessesAsync = ref.watch(workProcessListProvider);

    // Map machineId to steps count and SOP info
    final stepsCountByMachine = <String, int>{};
    final sopTitleByMachine = <String, String>{};
    workProcessesAsync.whenData((processes) {
      for (final p in processes) {
        if (p.machineId != null && p.machineId!.isNotEmpty) {
          final cur = stepsCountByMachine[p.machineId!] ?? 0;
          stepsCountByMachine[p.machineId!] = cur + p.steps.length;
          sopTitleByMachine[p.machineId!] = p.title;
        }
      }
    });

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.initialStation != null
                ? Icons.edit_note_rounded
                : Icons.add_circle_outline,
            color: Colors.blueAccent,
          ),
          const SizedBox(width: 8),
          Text(widget.initialStation != null
              ? 'แก้ไขสถานีงาน: ${widget.initialStation!.name}'
              : (widget.fromStationId != null
                  ? 'เพิ่มสถานีงานถัดไป'
                  : 'เพิ่มสถานีใหม่')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              machinesAsync.when(
                data: (machines) {
                  // Sort: Machines with SOP steps first
                  final sortedMachines = [...machines]..sort((a, b) {
                    final aCount = stepsCountByMachine[a.machineId] ?? 0;
                    final bCount = stepsCountByMachine[b.machineId] ?? 0;
                    if (aCount != bCount) return bCount.compareTo(aCount);
                    return a.machineNo.compareTo(b.machineNo);
                  });

                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'เลือกเครื่องจักร',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.precision_manufacturing_outlined),
                    ),
                    initialValue: selectedMachineId,
                    items: sortedMachines.map((m) {
                      final stepCount = stepsCountByMachine[m.machineId] ?? 0;
                      final hasSteps = stepCount > 0;
                      final mcNo = m.machineNo.trim();
                      final mcName = (m.machineName ?? 'Unknown Machine').trim();

                      return DropdownMenuItem<String>(
                        value: m.machineId,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                mcNo.isNotEmpty ? '[$mcNo] $mcName' : mcName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: hasSteps ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (hasSteps)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.teal, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, size: 12, color: Colors.teal),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$stepCount ขั้นตอน',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'ยังไม่มีขั้นตอน',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) async {
                      final chosen = val != null ? sortedMachines.firstWhere((m) => m.machineId == val) : null;
                      final stepCount = val != null ? (stepsCountByMachine[val] ?? 0) : 0;
                      final title = val != null ? sopTitleByMachine[val] : null;

                      setState(() {
                        selectedMachineId = val;
                        selectedMachineName = chosen?.machineName;
                        selectedMachineNo = chosen?.machineNo;
                        selectedMachineStepCount = stepCount;
                        selectedSopTitle = title;
                        if (val != null) {
                          name = chosen?.machineName ?? 'Station';
                          isCalculating = true;
                        } else {
                          name = _nameController.text;
                          energyCost = 0.0;
                        }
                      });

                      if (val != null) {
                        final data = await widget.notifier.fetchMachineDataForBalancing(val);
                        if (data != null && mounted) {
                          setState(() {
                            if (data.cycleTime > 0) {
                              cycleTime = data.cycleTime;
                              _cycleTimeController.text = cycleTime.toStringAsFixed(2);
                            }
                            energyCost = data.energyCost;
                            workers = data.workers;
                          });
                        }
                        if (mounted) {
                          setState(() {
                            isCalculating = false;
                          });
                        }
                      }
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Error loading machines: $e'),
              ),

              if (selectedMachineId != null) ...[
                const SizedBox(height: 12),
                if (selectedMachineStepCount > 0)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.task_alt_rounded, color: Colors.teal, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ดึงข้อมูลขั้นตอน SOP: $selectedMachineStepCount ขั้นตอน',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                              if (selectedSopTitle != null && selectedSopTitle!.isNotEmpty)
                                Text(
                                  selectedSopTitle!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.teal.shade700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 2),
                              Text(
                                'Cycle Time คำนวณจากขั้นตอนรวม: ${cycleTime.toStringAsFixed(1)} วินาที (${(cycleTime / 60).toStringAsFixed(1)} นาที)',
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '💡 เครื่องจักรนี้ยังไม่ได้กำหนดขั้นตอนการทำงาน (SOP) ในระบบ',
                            style: TextStyle(fontSize: 11.5, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),
                // Building & Room
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buildingController,
                        decoration: const InputDecoration(
                          labelText: 'อาคาร (Building)',
                          hintText: 'เช่น อาคาร 1, อาคาร 2',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.apartment_rounded, size: 18),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _roomController,
                        decoration: const InputDecoration(
                          labelText: 'ห้อง (Room)',
                          hintText: 'เช่น ห้องอัดแคปซูล 1',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.meeting_room_outlined, size: 18),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                // Secondary / Backup Machines Selector
                machinesAsync.when(
                  data: (machines) {
                    final candidateBackups = machines.where((m) => m.machineId != selectedMachineId).toList();
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.blueGrey),
                              const SizedBox(width: 6),
                              const Text(
                                'เครื่องจักรรอง / เครื่องสำรอง (Backup Machines)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Text(
                                '${secondaryMachineIds.length} เครื่อง',
                                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (candidateBackups.isEmpty)
                            const Text('ไม่มีเครื่องจักรอื่น', style: TextStyle(fontSize: 11, color: Colors.grey))
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: candidateBackups.map((m) {
                                final isSelected = secondaryMachineIds.contains(m.machineId);
                                final label = m.machineNo.isNotEmpty ? '[${m.machineNo}] ${m.machineName ?? ''}' : (m.machineName ?? '');
                                return FilterChip(
                                  selected: isSelected,
                                  label: Text(label, style: const TextStyle(fontSize: 11)),
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) {
                                        if (m.machineId != null && !secondaryMachineIds.contains(m.machineId)) {
                                          secondaryMachineIds.add(m.machineId!);
                                        }
                                      } else {
                                        secondaryMachineIds.remove(m.machineId);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],

              if (isCalculating)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('กำลังดึงข้อมูลและคำนวณ Cycle Time...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: selectedMachineId == null ? null : () {
            final bld = _buildingController.text.trim().isEmpty ? null : _buildingController.text.trim();
            final rm = _roomController.text.trim().isEmpty ? null : _roomController.text.trim();
            if (widget.initialStation != null) {
              widget.notifier.updateStation(
                widget.initialStation!.id,
                name,
                cycleTime,
                machineId: selectedMachineId,
                machineName: selectedMachineName,
                secondaryMachineIds: secondaryMachineIds,
                building: bld,
                room: rm,
                workers: workers,
                laborCost: laborCost,
                energyCost: energyCost,
                materialCost: materialCost,
                otherCost: otherCost,
                waitingTimeSec: waitingTimeSec,
                bufferQuantity: bufferQuantity,
              );
            } else {
              widget.notifier.addStation(
                name,
                cycleTime,
                machineId: selectedMachineId,
                machineName: selectedMachineName,
                secondaryMachineIds: secondaryMachineIds,
                building: bld,
                room: rm,
                workers: workers,
                laborCost: laborCost,
                energyCost: energyCost,
                materialCost: materialCost,
                otherCost: otherCost,
                waitingTimeSec: waitingTimeSec,
                bufferQuantity: bufferQuantity,
                prevStationIds: widget.fromStationId != null ? [widget.fromStationId!] : const [],
                position: widget.suggestedPosition ?? Offset.zero,
              );
            }
            Navigator.pop(context);
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
