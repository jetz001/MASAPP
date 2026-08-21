import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/ai_service.dart';
import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/providers/work_process_provider.dart';
import '../models/lean_metrics_model.dart';

final selectedProcessIdProvider = StateProvider<String?>((ref) => null);

final leanMetricsProvider = FutureProvider<LeanProcessMetrics?>((ref) async {
  final processList = await ref.watch(workProcessListProvider.future);
  final selectedId = ref.watch(selectedProcessIdProvider);

  if (processList.isEmpty) return null;

  final activeProcess = selectedId != null
      ? processList.firstWhere(
          (p) => p.processId == selectedId,
          orElse: () => processList.first,
        )
      : processList.first;

  WorkProcess? baseline;
  if (activeProcess.parentProcessId != null && activeProcess.parentProcessId!.isNotEmpty) {
    baseline = processList.cast<WorkProcess?>().firstWhere(
      (p) => p?.processId == activeProcess.parentProcessId,
      orElse: () => null,
    );
  } else if (activeProcess.methodType == WorkProcessMethodType.improved) {
    // Look for matching current process with same title or processNo
    baseline = processList.cast<WorkProcess?>().firstWhere(
      (p) => p?.methodType == WorkProcessMethodType.current &&
          (p?.processNo == activeProcess.processNo.replaceAll('-IMP', '') ||
              p?.title == activeProcess.title.replaceAll(' (ฉบับปรับปรุง)', '')),
      orElse: () => null,
    );
  }

  return LeanProcessMetrics(process: activeProcess, baselineProcess: baseline);
});

final aiLeanConsultantProvider =
    StateNotifierProvider<AiLeanConsultantNotifier, AsyncValue<String?>>((ref) {
  return AiLeanConsultantNotifier();
});

class AiLeanConsultantNotifier extends StateNotifier<AsyncValue<String?>> {
  AiLeanConsultantNotifier() : super(const AsyncValue.data(null));

  Future<void> analyzeProcess(WorkProcess process) async {
    state = const AsyncValue.loading();
    try {
      final config = await AiService.loadConfig();
      if (!config.isComplete) {
        throw Exception('ยังไม่ได้ตั้งค่า AI Provider หรือ API Key');
      }

      final stepsSummary = process.steps
          .map((s) =>
              '${s.stepNo}. [${s.eventType.label}] ${s.description} | เวลา: ${s.durationMinutes} นาที | ระยะทาง: ${s.distanceMeters} ม. | ประเภทคุณค่า: ${s.valueType.label} | สาเหตุปัญหา: ${s.problemCause ?? "-"}')
          .join('\n');

      final prompt = '''
คุณคือผู้เชี่ยวชาญด้านวิศวกรรมอุตสาหการและ Lean Manufacturing (Toyota Production System / Kaizen Consultant)
ช่วยวิเคราะห์ข้อมูลขั้นตอนการทำงาน (Process Flow Chart) ด้านล่างนี้ และให้ข้อเสนอแนะในการปรับปรุงแบบ ECRS (Eliminate, Combine, Rearrange, Simplify):

ชื่องาน: ${process.title} (รหัส: ${process.processNo})
วิธีการ: ${process.methodType.label} | ประเภท: ${process.workType.label}
เวลารวม: ${process.totalDurationMinutes} นาที | ระยะทางรวม: ${process.totalDistanceMeters} ม.
เวลาจำเป็น (VA): ${process.vaDurationMinutes} นาที (${process.processCycleEfficiency.toStringAsFixed(1)}%)
เวลาสูญเปล่า (Waste): ${(process.nvaDurationMinutes + process.nnvaDurationMinutes)} นาที (${process.wasteRatio.toStringAsFixed(1)}%)

ขั้นตอนการทำงาน:
$stepsSummary

กรุณาวิเคราะห์และจัดทำข้อเสนอแนะในรูปแบบ Markdown หัวข้อดังนี้:
1. 🔍 **สรุปจุดสูญเปล่าที่พบ (7 Wastes / Muda Analysis)**
2. 🚀 **ข้อเสนอแนะการปรับปรุงตามหลัก ECRS**:
   - **E (Eliminate - กำจัดทิ้ง)**: ขั้นตอนใดควรตัดทิ้งทันที
   - **C (Combine - รวมขั้นตอน)**: ขั้นตอนใดควรรวมเข้าด้วยกัน
   - **R (Rearrange - จัดลำดับใหม่)**: ขั้นตอนใดควรย้ายลำดับเพื่อลดระยะทาง/การรอคอย
   - **S (Simplify - ทำให้ง่ายขึ้น)**: ขั้นตอนใดควรใช้เครื่องมือ/Poka-Yoke หรืออุปกรณ์ช่วย
3. 📈 **การประเมินผลลัพธ์ที่คาดว่าจะได้รับ (Estimated Lead Time & Distance Reduction)**
''';

      final res = await AiService.chat(
        config: config,
        history: [],
        userMessage: prompt,
      );

      state = AsyncValue.data(res.text);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void clear() {
    state = const AsyncValue.data(null);
  }
}
