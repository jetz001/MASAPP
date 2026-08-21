import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'line_balancing_provider.dart';
import '../machine_intake/machine_provider.dart';

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

    return AlertDialog(
      title: const Text('เพิ่มสถานีใหม่'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            machinesAsync.when(
              data: (machines) {
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'เลือกเครื่องจักร'),
                  initialValue: selectedMachineId,
                  items: machines.map((m) => DropdownMenuItem(
                    value: m.machineId,
                    child: Text(m.machineName ?? 'Unknown Machine'),
                  )).toList(),
                  onChanged: (val) async {
                    setState(() {
                      selectedMachineId = val;
                      if (val != null) {
                        selectedMachineName = machines.firstWhere((m) => m.machineId == val).machineName;
                        name = selectedMachineName ?? 'Station';
                        isCalculating = true;
                      } else {
                        selectedMachineName = null;
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
              loading: () => const CircularProgressIndicator(),
              error: (e, st) => Text('Error loading machines: '),
            ),

            if (isCalculating)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('กำลังดึงข้อมูลเครื่องจักร...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
          ],
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
