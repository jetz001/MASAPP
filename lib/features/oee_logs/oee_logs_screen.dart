import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'oee_log_provider.dart';

class OeeLogsScreen extends ConsumerStatefulWidget {
  const OeeLogsScreen({super.key});

  @override
  ConsumerState<OeeLogsScreen> createState() => _OeeLogsScreenState();
}

class _OeeLogsScreenState extends ConsumerState<OeeLogsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _machineCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _actualCtrl = TextEditingController();
  final _goodCtrl = TextEditingController();

  bool _usePlc = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _machineCtrl.dispose();
    _hoursCtrl.dispose();
    _targetCtrl.dispose();
    _actualCtrl.dispose();
    _goodCtrl.dispose();
    super.dispose();
  }

  void _mockPlcData() {
    if (_usePlc) {
      _hoursCtrl.text = '8.0';
      _targetCtrl.text = '1000';
      _actualCtrl.text = '950';
      _goodCtrl.text = '935';
    } else {
      _hoursCtrl.clear();
      _targetCtrl.clear();
      _actualCtrl.clear();
      _goodCtrl.clear();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Hardcoded machine ID for demo, usually comes from dropdown
    final machineId = _machineCtrl.text.isEmpty ? 'MCH-001' : _machineCtrl.text;
    
    await ref.read(oeeLogProvider.notifier).addLog(
      machineId: machineId,
      hours: double.parse(_hoursCtrl.text),
      target: double.parse(_targetCtrl.text),
      actual: double.parse(_actualCtrl.text),
      good: double.parse(_goodCtrl.text),
      dataSource: _usePlc ? 'plc' : 'manual',
      date: _selectedDate,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกข้อมูล OEE เรียบร้อยแล้ว')),
    );
    
    _hoursCtrl.clear();
    _targetCtrl.clear();
    _actualCtrl.clear();
    _goodCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(oeeLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('บันทึก OEE & การทำงาน'),
      ),
      body: Row(
        children: [
          // Form Section
          Expanded(
            flex: 1,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      Text('บันทึกข้อมูลกะการทำงาน', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('รับข้อมูลจาก PLC อัตโนมัติ'),
                        subtitle: const Text('หากเปิด ระบบจะดึงค่าจาก iSoft/PLC อัตโนมัติ'),
                        value: _usePlc,
                        onChanged: (val) {
                          setState(() {
                            _usePlc = val;
                            _mockPlcData();
                          });
                        },
                      ),
                      const Divider(),
                      TextFormField(
                        controller: _machineCtrl,
                        decoration: const InputDecoration(labelText: 'รหัสเครื่องจักร (เช่น MCH-001)'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hoursCtrl,
                        decoration: const InputDecoration(labelText: 'ชั่วโมงเดินเครื่อง (ชม.)'),
                        keyboardType: TextInputType.number,
                        readOnly: _usePlc,
                        validator: (val) => val!.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _targetCtrl,
                        decoration: const InputDecoration(labelText: 'ยอดผลิตเป้าหมาย (ชิ้น)'),
                        keyboardType: TextInputType.number,
                        readOnly: _usePlc,
                        validator: (val) => val!.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _actualCtrl,
                        decoration: const InputDecoration(labelText: 'ยอดผลิตจริง (ชิ้น)'),
                        keyboardType: TextInputType.number,
                        readOnly: _usePlc,
                        validator: (val) => val!.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _goodCtrl,
                        decoration: const InputDecoration(labelText: 'ยอดของดี (ชิ้น)'),
                        keyboardType: TextInputType.number,
                        readOnly: _usePlc,
                        validator: (val) => val!.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _submit,
                        child: const Text('บันทึกข้อมูล'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // History Section
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
              child: logsAsync.when(
                data: (logs) {
                  return ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return ListTile(
                        leading: Icon(
                          log.dataSource == 'plc' ? Icons.memory : Icons.person,
                          color: log.dataSource == 'plc' ? Colors.blue : Colors.orange,
                        ),
                        title: Text('เครื่องจักร: ${log.machineId} (${log.cumulativeHours} ชม.)'),
                        subtitle: Text('ผลิตได้: ${log.actualProduction} / ${log.targetProduction} (ดี: ${log.goodProduction})'),
                        trailing: Text(log.recordedDate.toString().split(' ')[0]),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
