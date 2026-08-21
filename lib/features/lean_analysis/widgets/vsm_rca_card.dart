import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/ai_service.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/theme/app_spacing.dart';
import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';
import '../../work_processes/providers/work_process_provider.dart';

class VsmRcaCard extends ConsumerStatefulWidget {
  final WorkProcess process;
  final WorkProcessStep? initialStep;

  const VsmRcaCard({
    super.key,
    required this.process,
    this.initialStep,
  });

  @override
  ConsumerState<VsmRcaCard> createState() => _VsmRcaCardState();
}

class _VsmRcaCardState extends ConsumerState<VsmRcaCard> {
  WorkProcessStep? _selectedStep;
  bool _isGeneratingAi = false;
  bool _isSaving = false;

  final _why1Ctrl = TextEditingController();
  final _why2Ctrl = TextEditingController();
  final _why3Ctrl = TextEditingController();
  final _why4Ctrl = TextEditingController();
  final _why5Ctrl = TextEditingController();
  final _rootCauseCtrl = TextEditingController();
  final _correctiveCtrl = TextEditingController();
  final _preventiveCtrl = TextEditingController();

  final _fishboneManCtrl = TextEditingController();
  final _fishboneMachineCtrl = TextEditingController();
  final _fishboneMaterialCtrl = TextEditingController();
  final _fishboneMethodCtrl = TextEditingController();
  final _fishboneEnvCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initStepSelection();
  }

  @override
  void didUpdateWidget(covariant VsmRcaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStep != null && widget.initialStep != _selectedStep) {
      setState(() {
        _selectedStep = widget.initialStep;
        _populateFieldsFromStep(_selectedStep!);
      });
    }
  }

  void _initStepSelection() {
    if (widget.initialStep != null) {
      _selectedStep = widget.initialStep;
    } else if (widget.process.steps.isNotEmpty) {
      // Pick first bottleneck or first waste step
      _selectedStep = widget.process.steps.firstWhere(
        (s) => s.valueType == LeanValueType.nva || (s.problemCause?.isNotEmpty ?? false),
        orElse: () => widget.process.steps.first,
      );
    }
    if (_selectedStep != null) {
      _populateFieldsFromStep(_selectedStep!);
    }
  }

  void _populateFieldsFromStep(WorkProcessStep step) {
    _why1Ctrl.text = step.problemCause ?? '';
    _rootCauseCtrl.text = step.problemCause ?? '';
    _preventiveCtrl.text = step.improvementIdea ?? '';
  }

  @override
  void dispose() {
    _why1Ctrl.dispose();
    _why2Ctrl.dispose();
    _why3Ctrl.dispose();
    _why4Ctrl.dispose();
    _why5Ctrl.dispose();
    _rootCauseCtrl.dispose();
    _correctiveCtrl.dispose();
    _preventiveCtrl.dispose();
    _fishboneManCtrl.dispose();
    _fishboneMachineCtrl.dispose();
    _fishboneMaterialCtrl.dispose();
    _fishboneMethodCtrl.dispose();
    _fishboneEnvCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateAiRca() async {
    if (_selectedStep == null) return;
    setState(() => _isGeneratingAi = true);

    try {
      final s = _selectedStep!;
      final prompt = '''
กรุณาวิเคราะห์หาสาเหตุรากเหง้า (Root Cause Analysis - RCA) ด้วยหลักการ 5-Why และ Fishbone Diagram (ผังก้างปลา 4M1E) สำหรับขั้นตอนงานที่เป็นคอขวด/สูญเปล่าในโรงงาน:

กระบวนการ: ${widget.process.processNo} - ${widget.process.title}
ขั้นตอนที่ #${s.stepNo}: ${s.description}
ประเภทงาน: ${s.eventName} (${s.valueLabel})
เวลาที่ใช้: ${s.durationMinutes} นาที | ระยะทาง: ${s.distanceMeters} เมตร
ปัญหาที่พบเบื้องต้น: ${s.problemCause ?? 'มีความล่าช้าและเป็นคอขวดในกระบวนการ'}

กรุณาตอบในรูปแบบ JSON สั้นๆ ดังนี้เท่านั้น (ไม่มีข้อความอื่นนอกเหนือจาก JSON):
{
  "why_1": "ทำไมขั้นตอนนี้ถึงใช้เวลานาน/เกิดปัญหา",
  "why_2": "ทำไมข้อ 1 จึงเกิดขึ้น",
  "why_3": "ทำไมข้อ 2 จึงเกิดขึ้น",
  "why_4": "ทำไมข้อ 3 จึงเกิดขึ้น",
  "why_5": "ทำไมข้อ 4 จึงเกิดขึ้น (สาเหตุรากเหง้า)",
  "root_cause": "สรุปสาเหตุรากเหง้าที่แท้จริง",
  "corrective_action": "มาตรการแก้ไขชั่วคราวทันที",
  "preventive_action": "มาตรการป้องกันถาวรตามหลัก ECRS (Eliminate, Combine, Rearrange, Simplify)",
  "fishbone_man": "สาเหตุปัจจัยด้านคน/ทักษะ",
  "fishbone_machine": "สาเหตุปัจจัยด้านเครื่องจักร/อุปกรณ์",
  "fishbone_material": "สาเหตุปัจจัยด้านวัตถุดิบ/ชิ้นงาน",
  "fishbone_method": "สาเหตุปัจจัยด้านวิธีการ/ขั้นตอน",
  "fishbone_environment": "สาเหตุปัจจัยด้านสภาพแวดล้อม/สถานที่"
}
''';

      final result = await AiService.chat(
        history: [],
        userMessage: prompt,
      );

      final text = result.text.trim();
      final jsonStart = text.indexOf('{');
      final jsonEnd = text.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        final rawJson = text.substring(jsonStart, jsonEnd + 1);
        // Simple regex extractor fallback for robustness
        String extractKey(String key) {
          final reg = RegExp('"$key"\\s*:\\s*"([^"]+)"');
          final match = reg.firstMatch(rawJson);
          return match?.group(1) ?? '';
        }

        setState(() {
          _why1Ctrl.text = extractKey('why_1');
          _why2Ctrl.text = extractKey('why_2');
          _why3Ctrl.text = extractKey('why_3');
          _why4Ctrl.text = extractKey('why_4');
          _why5Ctrl.text = extractKey('why_5');
          _rootCauseCtrl.text = extractKey('root_cause');
          _correctiveCtrl.text = extractKey('corrective_action');
          _preventiveCtrl.text = extractKey('preventive_action');

          _fishboneManCtrl.text = extractKey('fishbone_man');
          _fishboneMachineCtrl.text = extractKey('fishbone_machine');
          _fishboneMaterialCtrl.text = extractKey('fishbone_material');
          _fishboneMethodCtrl.text = extractKey('fishbone_method');
          _fishboneEnvCtrl.text = extractKey('fishbone_environment');
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ AI วิเคราะห์ 5-Why และผังก้างปลา (Fishbone) สำเร็จแล้ว'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการวิเคราะห์ AI: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingAi = false);
      }
    }
  }

  Future<void> _saveRcaToProcess() async {
    if (_selectedStep == null) return;
    setState(() => _isSaving = true);

    try {
      final s = _selectedStep!;
      final rootCause = _rootCauseCtrl.text.trim();
      final preventive = _preventiveCtrl.text.trim();

      // Update work_process_steps with RCA findings
      await DbHelper.execute('''
        UPDATE work_process_steps
        SET problem_cause = @cause,
            improvement_idea = @idea
        WHERE step_id = @id
      ''', params: {
        'id': s.stepId,
        'cause': rootCause.isNotEmpty ? rootCause : _why1Ctrl.text.trim(),
        'idea': preventive,
      });

      // Invalidate provider to refresh
      ref.invalidate(workProcessListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกผลการวิเคราะห์ RCA ลงในขั้นตอน #${s.stepNo} สำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header & Step Picker
            _buildRcaHeader(theme, isDark),
            const Divider(height: 28),

            // 2. Step Selector Dropdown
            _buildStepSelector(theme, isDark),
            const SizedBox(height: 20),

            // 3. 5-Why Analysis Stepper
            _build5WhySection(theme, isDark),
            const SizedBox(height: 24),

            // 4. Fishbone Diagram (Ishikawa 4M1E)
            _buildFishboneSection(theme, isDark),
            const SizedBox(height: 24),

            // 5. Countermeasures (Corrective & Preventive ECRS)
            _buildCountermeasureSection(theme, isDark),
            const SizedBox(height: 24),

            // 6. Action Buttons
            _buildActionButtons(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildRcaHeader(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.deepOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.troubleshoot_rounded,
            color: Colors.deepOrange,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'การวิเคราะห์สาเหตุรากเหง้าคอขวด (VSM Bottleneck RCA & 5-Why)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'เจาะลึกหาสาเหตุที่แท้จริงของความล่าช้า/ความสูญเปล่าใน Value Stream ด้วยเทคนิค 5-Why และผังก้างปลา (4M1E)',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: _isGeneratingAi ? null : _generateAiRca,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          icon: _isGeneratingAi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(_isGeneratingAi ? 'AI กำลังวิเคราะห์...' : '🤖 AI วิเคราะห์ RCA 5-Why'),
        ),
      ],
    );
  }

  Widget _buildStepSelector(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.deepOrange.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded, color: Colors.deepOrange, size: 20),
          const SizedBox(width: 10),
          const Text(
            'เลือกขั้นตอนที่ต้องการทำ RCA: ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<WorkProcessStep>(
                value: _selectedStep,
                isExpanded: true,
                items: widget.process.steps.map((s) {
                  final isWaste = s.valueType == LeanValueType.nva;
                  final isDelay = s.eventType == ProcessEventType.delay;

                  return DropdownMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Text(s.eventIcon),
                        const SizedBox(width: 8),
                        Text('#${s.stepNo} ${s.description} (${s.durationMinutes}m)'),
                        const Spacer(),
                        if (isWaste)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red),
                            ),
                            child: const Text('💥 สูญเปล่า', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                        else if (isDelay)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: const Text('⏳ คอขวด/ล่าช้า', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedStep = val;
                      _populateFieldsFromStep(val);
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build5WhySection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Text(
              'ลำดับขั้นการสืบหาสาเหตุ 5-Why (5-Why Root Cause Drill-down)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildWhyInputRow(1, 'ทำไม (Why 1): ทำไมขั้นตอนนี้จึงล่าช้าหรือเกิดปัญหา?', _why1Ctrl, Colors.blue.shade700),
        _buildWhyInputRow(2, 'ทำไม (Why 2): ทำไมข้อ 1 จึงเกิดขึ้น?', _why2Ctrl, Colors.indigo),
        _buildWhyInputRow(3, 'ทำไม (Why 3): ทำไมข้อ 2 จึงเกิดขึ้น?', _why3Ctrl, Colors.deepPurple),
        _buildWhyInputRow(4, 'ทำไม (Why 4): ทำไมข้อ 3 จึงเกิดขึ้น?', _why4Ctrl, Colors.purple),
        _buildWhyInputRow(5, 'ทำไม (Why 5): ทำไมข้อ 4 จึงเกิดขึ้น (ต้นเหตุแท้จริง)?', _why5Ctrl, Colors.pink.shade700),
        const SizedBox(height: 10),
        // Root cause final box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: isDark ? 0.2 : 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.crisis_alert_rounded, color: Colors.red, size: 18),
                  SizedBox(width: 6),
                  Text(
                    '🎯 สรุปสาเหตุรากเหง้า (Root Cause Summary)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _rootCauseCtrl,
                decoration: const InputDecoration(
                  hintText: 'ระบุสาเหตุรากเหง้าหลักที่ทำให้เกิดความสูญเปล่านี้...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWhyInputRow(int level, String label, TextEditingController ctrl, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$level',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(fontSize: 11, color: color),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFishboneSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_rounded, color: Colors.teal, size: 20),
            const SizedBox(width: 8),
            Text(
              'ผังก้างปลาจำแนก 5 มิติ (Ishikawa Diagram 4M1E)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildFishboneBox('👤 คน (Man)', 'ทักษะ, จำนวนช่าง, การสื่อสาร', _fishboneManCtrl, Colors.blue, isDark)),
            const SizedBox(width: 8),
            Expanded(child: _buildFishboneBox('⚙️ เครื่องจักร (Machine)', 'ความพร้อม, ชำรุด, ติดขัด', _fishboneMachineCtrl, Colors.orange, isDark)),
            const SizedBox(width: 8),
            Expanded(child: _buildFishboneBox('📦 วัตถุดิบ (Material)', 'ขาดสต็อก, คุณภาพ, รอนาน', _fishboneMaterialCtrl, Colors.amber.shade800, isDark)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildFishboneBox('📋 วิธีการ (Method)', 'ขั้นตอนซับซ้อน, ไม่มี SOP', _fishboneMethodCtrl, Colors.purple, isDark)),
            const SizedBox(width: 8),
            Expanded(child: _buildFishboneBox('🌡️ สภาพแวดล้อม (Environment)', 'พื้นที่คับแคบ, ร้อน, มืด', _fishboneEnvCtrl, Colors.teal, isDark)),
          ],
        ),
      ],
    );
  }

  Widget _buildFishboneBox(String title, String hint, TextEditingController ctrl, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 11),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.all(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountermeasureSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              'มาตรการแก้ไขและป้องกัน (Corrective & Preventive Action - ECRS)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _correctiveCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '🛠️ มาตรการแก้ไขเฉพาะหน้า (Corrective Action)',
                  hintText: 'การดำเนินการแก้ไขทันทีเพื่อปลดล็อกคอขวด...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _preventiveCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '🛡️ มาตรการป้องกันถาวร (Preventive ECRS Countermeasure)',
                  hintText: 'แนวทางขจัด (Eliminate), รวม (Combine), หรือทำให้ง่าย (Simplify)...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _why1Ctrl.clear();
              _why2Ctrl.clear();
              _why3Ctrl.clear();
              _why4Ctrl.clear();
              _why5Ctrl.clear();
              _rootCauseCtrl.clear();
              _correctiveCtrl.clear();
              _preventiveCtrl.clear();
              _fishboneManCtrl.clear();
              _fishboneMachineCtrl.clear();
              _fishboneMaterialCtrl.clear();
              _fishboneMethodCtrl.clear();
              _fishboneEnvCtrl.clear();
            });
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('ล้างข้อมูลฟอร์ม'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveRcaToProcess,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_rounded, size: 16),
          label: Text(_isSaving ? 'กำลังบันทึก...' : '💾 บันทึกผล RCA ลงในกระบวนการ'),
        ),
      ],
    );
  }
}
