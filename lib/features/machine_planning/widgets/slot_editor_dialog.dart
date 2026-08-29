import 'package:flutter/material.dart';
import '../models/machine_plan_models.dart';

class SlotEditorDialog extends StatefulWidget {
  final String machineName;
  final String dayLabel;
  final DayScheduleSlot initialSlot;

  const SlotEditorDialog({
    super.key,
    required this.machineName,
    required this.dayLabel,
    required this.initialSlot,
  });

  static Future<DayScheduleSlot?> show(
    BuildContext context, {
    required String machineName,
    required String dayLabel,
    required DayScheduleSlot initialSlot,
  }) {
    return showDialog<DayScheduleSlot>(
      context: context,
      builder: (ctx) => SlotEditorDialog(
        machineName: machineName,
        dayLabel: dayLabel,
        initialSlot: initialSlot,
      ),
    );
  }

  @override
  State<SlotEditorDialog> createState() => _SlotEditorDialogState();
}

class _SlotEditorDialogState extends State<SlotEditorDialog> {
  late TextEditingController _timeController;
  late bool _isOt;
  late String _colorKey;

  @override
  void initState() {
    super.initState();
    _timeController = TextEditingController(text: widget.initialSlot.time);
    _isOt = widget.initialSlot.isOt;
    _colorKey = widget.initialSlot.colorKey ?? (_isOt ? 'orange' : 'yellow');
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  void _applyPreset(SchedulePreset preset) {
    setState(() {
      _timeController.text = preset.time;
      _isOt = preset.isOt;
      _colorKey = preset.colorKey;
    });
  }

  void _clear() {
    setState(() {
      _timeController.text = '';
      _isOt = false;
      _colorKey = 'yellow';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.access_time_filled_rounded, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ตั้งเวลาทำงาน: วัน${widget.dayLabel}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.machineName,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick Presets
              const Text(
                '⚡ เลือกช่วงเวลายอดนิยม (Quick Presets):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...kStandardPresets.map((preset) {
                    final isSelected =
                        _timeController.text == preset.time && _isOt == preset.isOt;
                    return ChoiceChip(
                      label: Text(preset.label, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      selectedColor: preset.isOt
                          ? Colors.orange.shade200
                          : Colors.amber.shade200,
                      onSelected: (_) => _applyPreset(preset),
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                    label: const Text('เว้นว่าง / หยุด', style: TextStyle(fontSize: 11, color: Colors.red)),
                    onPressed: _clear,
                  ),
                ],
              ),

              const Divider(height: 24),

              // Custom Time Input
              const Text(
                '⏱️ หรือระบุช่วงเวลาเอง (Custom Time):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _timeController,
                decoration: InputDecoration(
                  labelText: 'ช่วงเวลา (เช่น 08:00-17:00)',
                  hintText: '08:00-17:00',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.schedule, size: 18),
                  suffixIcon: _timeController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _timeController.clear()),
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 12),

              // OT Checkbox
              Container(
                decoration: BoxDecoration(
                  color: _isOt
                      ? Colors.orange.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isOt ? Colors.orange : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: CheckboxListTile(
                  value: _isOt,
                  title: Row(
                    children: [
                      const Text(
                        'เป็นช่วงเวลาทำงานล่วงเวลา (OT)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      if (_isOt)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'OT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: const Text(
                    'จะแสดงตัวหนังสือ OT ตัวหนาและไฮไลต์สีส้ม/แดงในตารางและ PDF',
                    style: TextStyle(fontSize: 10.5),
                  ),
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _isOt = val ?? false;
                      if (_isOt) {
                        _colorKey = 'orange';
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () {
            final text = _timeController.text.trim();
            final result = DayScheduleSlot(
              time: text,
              isOt: _isOt,
              colorKey: _colorKey,
            );
            Navigator.pop(context, result);
          },
          child: const Text('นำไปใช้'),
        ),
      ],
    );
  }
}
