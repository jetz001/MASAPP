import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'line_balancing_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../work_processes/providers/work_process_provider.dart';

class AddStationDialog extends ConsumerStatefulWidget {
  final LineBalancingNotifier notifier;
  const AddStationDialog({super.key, required this.notifier});

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
  int selectedMachineStepCount = 0;
  String? selectedSopTitle;
  bool isCalculating = false;

  double laborCost = 300.0;
  double energyCost = 0.0;
  double materialCost = 0.0;
  double otherCost = 0.0;

  final TextEditingController _cycleTimeController = TextEditingController(text: '20.0');
  final TextEditingController _nameController = TextEditingController(text: 'Station');
  final TextEditingController _workersController = TextEditingController(text: '1');
  
  final TextEditingController _laborCostController = TextEditingController(text: '300.0');
  final TextEditingController _energyCostController = TextEditingController(text: '0.0');
  final TextEditingController _materialCostController = TextEditingController(text: '0.0');
  final TextEditingController _otherCostController = TextEditingController(text: '0.0');

  @override
  void dispose() {
    _cycleTimeController.dispose();
    _nameController.dispose();
    _workersController.dispose();
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
      title: const Row(
        children: [
          Icon(Icons.add_circle_outline, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text('เพิ่มสถานีใหม่'),
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
            widget.notifier.addStation(
              name, 
              cycleTime, 
              machineId: selectedMachineId, 
              machineName: selectedMachineName,
              workers: workers,
              laborCost: laborCost,
              energyCost: energyCost,
              materialCost: materialCost,
              otherCost: otherCost,
            );
            Navigator.pop(context);
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
