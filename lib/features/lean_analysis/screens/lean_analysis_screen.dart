import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';
import '../../work_processes/providers/work_process_provider.dart';
import '../../line_balancing/line_balancing_provider.dart';
import '../models/lean_metrics_model.dart';
import '../providers/lean_analysis_provider.dart';
import '../widgets/vsm_visualizer_card.dart';
import '../widgets/vsm_rca_card.dart';

class LeanAnalysisScreen extends ConsumerStatefulWidget {
  final String? initialProcessId;
  const LeanAnalysisScreen({super.key, this.initialProcessId});

  @override
  ConsumerState<LeanAnalysisScreen> createState() => _LeanAnalysisScreenState();
}

class _LeanAnalysisScreenState extends ConsumerState<LeanAnalysisScreen> {
  int _sourceMode = 0; // 0: Line Balancing, 1: Machine SOPs
  int _selectedTab = 0; // 0: Dashboard, 1: VSM, 2: RCA
  WorkProcessStep? _rcaTargetStep;

  @override
  void initState() {
    super.initState();
    if (widget.initialProcessId != null) {
      _sourceMode = 1; // SOP mode
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedProcessIdProvider.notifier).state =
            widget.initialProcessId;
      });
    }
  }

  WorkProcess _convertLineToWorkProcess(LineBalancingState lineState) {
    final steps = <WorkProcessStep>[];
    for (int i = 0; i < lineState.stations.length; i++) {
      final s = lineState.stations[i];

      // If station has buffer/waiting time, prepend a delay step
      if (s.waitingTimeSec > 0) {
        steps.add(
          WorkProcessStep(
            stepId: 'buf_${s.id}',
            processId: lineState.lineId,
            stepNo: steps.length + 1,
            description:
                'รอคอย/สต็อกคั่นหน้าสถานี ${s.name} ${s.bufferQuantity > 0 ? "(${s.bufferQuantity} ชิ้น)" : ""}',
            eventType: ProcessEventType.delay,
            durationMinutes: s.waitingTimeSec / 60.0,
            valueType: LeanValueType.nva,
            problemCause: 'เวลารอคอย/Buffer ก่อนเข้าสถานี ${s.name}',
            improvementIdea: 'ปรับปรุง Line Balancing เพื่อลดเวลารอคอยและ WIP',
            createdAt: DateTime.now(),
          ),
        );
      }

      ProcessEventType evt;
      switch (s.eventType) {
        case 'transportation':
          evt = ProcessEventType.transportation;
          break;
        case 'inspection':
          evt = ProcessEventType.inspection;
          break;
        case 'delay':
          evt = ProcessEventType.delay;
          break;
        case 'storage':
          evt = ProcessEventType.storage;
          break;
        default:
          evt = ProcessEventType.operation;
      }

      LeanValueType val;
      switch (s.valueType) {
        case 'nva':
          val = LeanValueType.nva;
          break;
        case 'nnva':
          val = LeanValueType.nnva;
          break;
        default:
          val = LeanValueType.va;
      }

      steps.add(
        WorkProcessStep(
          stepId: s.id,
          processId: lineState.lineId,
          stepNo: steps.length + 1,
          description:
              'สถานีที่ ${i + 1}: ${s.name}${s.machineName != null && s.machineName!.isNotEmpty ? " [${s.machineName}]" : ""}',
          eventType: evt,
          durationMinutes: s.cycleTime / 60.0,
          valueType: val,
          toolsUsed: s.machineName,
          partsQuantity: '${s.workers} คน',
          createdAt: DateTime.now(),
        ),
      );
    }

    final now = DateTime.now();
    return WorkProcess(
      processId: lineState.lineId,
      processNo: 'LINE-${lineState.lineName.replaceAll(' ', '')}',
      title: 'สายการผลิต: ${lineState.lineName}',
      methodType: WorkProcessMethodType.current,
      workType: WorkTypeCategory.product,
      department: lineState.department ?? 'ฝ่ายผลิต / ซ่อมบำรุง',
      status: 'active',
      steps: steps,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processListAsync = ref.watch(workProcessListProvider);
    final metricsAsync = ref.watch(leanMetricsProvider);
    final aiConsultantState = ref.watch(aiLeanConsultantProvider);
    final lineState = ref.watch(lineBalancingProvider);
    final allLinesAsync = ref.watch(allProductionLinesProvider);

    final processes = processListAsync.valueOrNull ?? [];
    final savedLines = allLinesAsync.valueOrNull ?? [];

    // Current active process depending on sourceMode
    WorkProcess? activeProcess;
    if (_sourceMode == 0) {
      if (lineState.stations.isNotEmpty) {
        activeProcess = _convertLineToWorkProcess(lineState);
      }
    } else {
      if (processes.isNotEmpty) {
        final selectedId = ref.watch(selectedProcessIdProvider) ??
            processes.first.processId;
        activeProcess = processes.firstWhere(
          (p) => p.processId == selectedId,
          orElse: () => processes.first,
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.analytics_rounded,
                size: 20,
                color: Colors.amber,
              ),
            ),
            const SizedBox(width: 12),
            const Text('การวิเคราะห์ Lean & Value Stream Mapping (VSM) & RCA'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree_rounded),
            tooltip: 'ไปที่หน้า Line Balancing',
            onPressed: () => context.push('/line-balancing'),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_bulleted_rounded),
            tooltip: 'ไปที่รายการขั้นตอนการทำงาน SOP',
            onPressed: () => context.push('/work-processes'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // 1. Source Selector (Line Balancing vs Machine SOPs)
          _buildSourceModeSelector(theme, savedLines, processes),
          const SizedBox(height: AppSpacing.md),

          // 2. Specific Line / Process Selector
          if (_sourceMode == 0)
            _buildLineBalancingSelectorCard(theme, lineState, savedLines)
          else if (processes.isNotEmpty)
            _buildProcessSelectorCard(processes, theme),

          const SizedBox(height: AppSpacing.md),

          // 3. If in Line Balancing mode: Show Station Lean Classifier Table
          if (_sourceMode == 0 && lineState.stations.isNotEmpty) ...[
            _buildStationLeanClassifierCard(theme, lineState),
            const SizedBox(height: AppSpacing.md),
          ],

          // 4. Tab Navigation (Dashboard, VSM, RCA)
          Center(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.dashboard_rounded, size: 16),
                  label: Text('📊 สถิติ & เมทริกซ์ Lean'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.alt_route_rounded, size: 16),
                  label: Text('🗺️ สายธารคุณค่า (VSM)'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.troubleshoot_rounded, size: 16),
                  label: Text('🔍 วิเคราะห์คอขวด (RCA 5-Why)'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (newVal) {
                setState(() => _selectedTab = newVal.first);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 5. Active Tab Content
          if (activeProcess == null || activeProcess.steps.isEmpty) ...[
            _buildEmptyState(theme)
          ] else if (_selectedTab == 1) ...[
            VsmVisualizerCard(
              process: activeProcess,
              onSelectStepForRca: (step) {
                setState(() {
                  _rcaTargetStep = step;
                  _selectedTab = 2;
                });
              },
            ),
          ] else if (_selectedTab == 2) ...[
            VsmRcaCard(
              process: activeProcess,
              initialStep: _rcaTargetStep,
            ),
          ] else ...[
            // Tab 0: Dashboard Metrics
            if (_sourceMode == 0) ...[
              _buildLineBalancingDashboardOverview(theme, lineState),
              const SizedBox(height: AppSpacing.lg),
              _buildWasteStepsMatrix(
                LeanProcessMetrics(process: activeProcess),
                theme,
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildAiConsultantSection(
                LeanProcessMetrics(process: activeProcess),
                aiConsultantState,
                theme,
              ),
            ] else ...[
              metricsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) =>
                    Center(child: Text('คำนวณสถิติล้มเหลว: $err')),
                data: (metrics) {
                  if (metrics == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopOverviewCards(metrics, theme),
                      if (metrics.hasComparison) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _buildBeforeAfterCard(metrics, theme),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _buildAsmeBreakdownCard(metrics, theme),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            flex: 4,
                            child: _buildValueBreakdownCard(metrics, theme),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildWasteStepsMatrix(metrics, theme),
                      const SizedBox(height: AppSpacing.lg),
                      _buildAiConsultantSection(
                        metrics,
                        aiConsultantState,
                        theme,
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _sourceMode == 0
                  ? 'ยังไม่มีสถานีในสายการผลิต Line Balancing'
                  : 'ยังไม่มีข้อมูลขั้นตอนการทำงานสำหรับวิเคราะห์ Lean',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _sourceMode == 0
                  ? context.push('/line-balancing')
                  : context.push('/work-processes/new'),
              icon: const Icon(Icons.add),
              label: Text(
                _sourceMode == 0
                    ? 'ไปที่ Line Balancing เพื่อเพิ่มสถานี'
                    : 'สร้างขั้นตอนการทำงานใหม่',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceModeSelector(
    ThemeData theme,
    List<Map<String, dynamic>> lines,
    List<WorkProcess> processes,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, size: 20, color: Colors.indigo),
          const SizedBox(width: 12),
          const Text(
            'แหล่งข้อมูลที่ต้องการวิเคราะห์ Lean / VSM:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Spacer(),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                icon: const Icon(Icons.precision_manufacturing_rounded, size: 16),
                label: Text('🏭 สายการผลิต (${lines.length})'),
              ),
              ButtonSegment(
                value: 1,
                icon: const Icon(Icons.format_list_numbered_rounded, size: 16),
                label: Text('⚙️ ขั้นตอนงานประจำเครื่อง (${processes.length})'),
              ),
            ],
            selected: {_sourceMode},
            onSelectionChanged: (val) {
              setState(() => _sourceMode = val.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLineBalancingSelectorCard(
    ThemeData theme,
    LineBalancingState lineState,
    List<Map<String, dynamic>> savedLines,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.account_tree_rounded, color: Colors.indigo),
            const SizedBox(width: 12),
            const Text(
              'เลือกสายการผลิต:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: savedLines.any((l) => l['line_id'] == lineState.lineId)
                      ? lineState.lineId
                      : (savedLines.isNotEmpty
                          ? savedLines.first['line_id'].toString()
                          : null),
                  isExpanded: true,
                  hint: Text('${lineState.lineName} (${lineState.stations.length} สถานี)'),
                  items: [
                    if (savedLines.isEmpty)
                      DropdownMenuItem(
                        value: lineState.lineId,
                        child: Text('${lineState.lineName} (${lineState.stations.length} สถานี)'),
                      ),
                    ...savedLines.map((l) {
                      return DropdownMenuItem(
                        value: l['line_id'].toString(),
                        child: Text(
                          '${l['line_name']} — Takt: ${((((l['available_time_min'] as num?)?.toDouble() ?? 480) * 60) / (((l['demand_quantity'] as num?)?.toDouble() ?? 1000))).toStringAsFixed(1)}s',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(lineBalancingProvider.notifier).loadLine(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('จัดการ Line Balancing'),
              onPressed: () => context.push('/line-balancing'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessSelectorCard(
    List<WorkProcess> processes,
    ThemeData theme,
  ) {
    if (processes.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedId = ref.watch(selectedProcessIdProvider) ??
        processes.first.processId;
    final currentProcess = processes.firstWhere(
      (p) => p.processId == selectedId,
      orElse: () => processes.first,
    );

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.account_tree_rounded, color: Colors.blue),
            const SizedBox(width: 12),
            const Text(
              'เลือกขั้นตอนงานประจำเครื่อง: ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedId,
                  isExpanded: true,
                  items: processes.map((p) {
                    final isCurrent =
                        p.methodType == WorkProcessMethodType.current;
                    return DropdownMenuItem(
                      value: p.processId,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? Colors.blue.withValues(alpha: 0.15)
                                  : Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isCurrent ? Colors.blue : Colors.green,
                              ),
                            ),
                            child: Text(
                              isCurrent ? 'ปัจจุบัน' : 'ปรับปรุง',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isCurrent
                                    ? Colors.blue.shade700
                                    : Colors.green.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${p.processNo} — ${p.title}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(selectedProcessIdProvider.notifier).state = val;
                      ref.read(aiLeanConsultantProvider.notifier).clear();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('ดู/แก้ไขขั้นตอน'),
              onPressed: () =>
                  context.push('/work-processes/${currentProcess.processId}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationLeanClassifierCard(
    ThemeData theme,
    LineBalancingState lineState,
  ) {
    final notifier = ref.read(lineBalancingProvider.notifier);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded, size: 20, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  'กำหนดประเภทกิจกรรม Lean & สต็อกคั่น (WIP / Buffer) ประจำสถานี',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'ปรับเปลี่ยนประเภทเพื่อดูผล VSM และ PCE % ทันที',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 38,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                columns: const [
                  DataColumn(label: Text('ลำดับ', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('ชื่อสถานี / เครื่องจักร', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Cycle Time', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('สัญลักษณ์ ASME', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('ประเภทคุณค่า (Lean Value)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('เวลารอคอย/Buffer (วิ.)', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: lineState.stations.map((s) {
                  final idx = lineState.stations.indexOf(s) + 1;

                  return DataRow(
                    cells: [
                      DataCell(Text('#$idx', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            if (s.machineName != null && s.machineName!.isNotEmpty)
                              Text(s.machineName!, style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                          ],
                        ),
                      ),
                      DataCell(
                        Text('${s.cycleTime.toStringAsFixed(1)} วิ. (${(s.cycleTime / 60).toStringAsFixed(1)} นาที)'),
                      ),
                      DataCell(
                        DropdownButton<String>(
                          value: s.eventType,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 'operation', child: Text('⭕ ทำงาน (Operation)')),
                            DropdownMenuItem(value: 'transportation', child: Text('⇨ ขนส่ง (Transport)')),
                            DropdownMenuItem(value: 'inspection', child: Text('◻ ตรวจสอบ (Inspection)')),
                            DropdownMenuItem(value: 'delay', child: Text('D รอคอย (Delay)')),
                            DropdownMenuItem(value: 'storage', child: Text('▽ จัดเก็บ (Storage)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              notifier.updateStationLeanType(s.id, eventType: val);
                            }
                          },
                        ),
                      ),
                      DataCell(
                        DropdownButton<String>(
                          value: s.valueType,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            DropdownMenuItem(
                              value: 'va',
                              child: Text('🟢 มีมูลค่า (VA)', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                            ),
                            DropdownMenuItem(
                              value: 'nnva',
                              child: Text('🟡 จำเป็นแต่ไม่เพิ่มค่า (NNVA)', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                            ),
                            DropdownMenuItem(
                              value: 'nva',
                              child: Text('🔴 สูญเปล่า (NVA)', style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              notifier.updateStationLeanType(s.id, valueType: val);
                            }
                          },
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            initialValue: s.waitingTimeSec.toStringAsFixed(0),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              final numVal = double.tryParse(v) ?? 0.0;
                              notifier.updateStationLeanType(s.id, waitingTimeSec: numVal);
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineBalancingDashboardOverview(
    ThemeData theme,
    LineBalancingState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildMetricSummaryBox(
              'Takt Time (เป้าหมาย)',
              '${state.taktTimeSec.toStringAsFixed(1)} วิ./ชิ้น',
              'Demand: ${state.demandQuantity.toStringAsFixed(0)} ชิ้น/กะ',
              Icons.speed_rounded,
              Colors.blue,
              theme,
            ),
            const SizedBox(width: 12),
            _buildMetricSummaryBox(
              'ประสิทธิภาพไลน์ (Efficiency)',
              '${state.lineEfficiency.toStringAsFixed(1)}%',
              'Balance Delay: ${state.balanceDelay.toStringAsFixed(1)}%',
              Icons.bolt_rounded,
              state.lineEfficiency >= 80 ? Colors.green : Colors.orange,
              theme,
            ),
            const SizedBox(width: 12),
            _buildMetricSummaryBox(
              'VSM Efficiency (PCE)',
              '${state.processCycleEfficiency.toStringAsFixed(1)}%',
              'VA: ${(state.totalVaTimeSec / 60).toStringAsFixed(1)}m | NVA: ${(state.totalNvaTimeSec / 60).toStringAsFixed(1)}m',
              Icons.donut_large_rounded,
              state.processCycleEfficiency >= 50 ? Colors.teal : Colors.deepOrange,
              theme,
            ),
            const SizedBox(width: 12),
            _buildMetricSummaryBox(
              'Lead Time รวมต่อชิ้น',
              '${state.leadTimeSec.toStringAsFixed(1)} วิ.',
              'พนักงาน: ${state.totalWorkers} คน | ${state.stations.length} สถานี',
              Icons.timer_outlined,
              Colors.purple,
              theme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopOverviewCards(LeanProcessMetrics metrics, ThemeData theme) {
    return Row(
      children: [
        _buildMetricSummaryBox(
          'เวลารวม (Lead Time)',
          '${metrics.totalDurationMinutes.toStringAsFixed(1)} นาที',
          '${metrics.stepCount} ขั้นตอนงาน',
          Icons.timer_outlined,
          Colors.blue,
          theme,
        ),
        const SizedBox(width: 12),
        _buildMetricSummaryBox(
          'ประสิทธิภาพกระบวนการ (PCE)',
          '${metrics.processCycleEfficiency.toStringAsFixed(1)}%',
          'เวลาจำเป็น (VA): ${metrics.vaDurationMinutes.toStringAsFixed(1)} นาที',
          Icons.speed_rounded,
          metrics.processCycleEfficiency >= 50 ? Colors.green : Colors.orange,
          theme,
        ),
        const SizedBox(width: 12),
        _buildMetricSummaryBox(
          'สัดส่วนความสูญเปล่า (Waste)',
          '${metrics.wasteRatio.toStringAsFixed(1)}%',
          'เวลาสูญเปล่า: ${(metrics.nvaDurationMinutes + metrics.nnvaDurationMinutes).toStringAsFixed(1)} นาที',
          Icons.delete_sweep_rounded,
          metrics.wasteRatio > 30 ? Colors.red : Colors.green,
          theme,
        ),
        const SizedBox(width: 12),
        _buildMetricSummaryBox(
          'ระยะทางเคลื่อนย้ายรวม',
          '${metrics.totalDistanceMeters.toStringAsFixed(1)} เมตร',
          'ขนส่ง: ${metrics.eventCounts[ProcessEventType.transportation] ?? 0} ครั้ง',
          Icons.straighten_rounded,
          Colors.purple,
          theme,
        ),
      ],
    );
  }

  Widget _buildMetricSummaryBox(
    String title,
    String mainValue,
    String subValue,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              mainValue,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subValue,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeforeAfterCard(LeanProcessMetrics metrics, ThemeData theme) {
    final isFaster = metrics.timeSavedMinutes > 0;
    final isShorter = metrics.distanceSavedMeters > 0;

    return Card(
      color: Colors.green.shade500.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade400, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.trending_down_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'ผลลัพธ์การปรับปรุง (Before vs After Comparison)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                const Spacer(),
                Text(
                  'เปรียบเทียบกับ: ${metrics.baselineProcess?.processNo ?? "ฉบับเดิม"}',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildComparisonStat(
                  'เวลาที่ประหยัดได้',
                  '${metrics.timeSavedMinutes.abs().toStringAsFixed(1)} นาที',
                  'ลดลง ${metrics.timeSavedPercent.toStringAsFixed(1)}%',
                  isFaster ? Colors.green : Colors.red,
                ),
                _buildComparisonStat(
                  'ระยะทางที่ลดลง',
                  '${metrics.distanceSavedMeters.abs().toStringAsFixed(1)} ม.',
                  'ลดลง ${metrics.distanceSavedPercent.toStringAsFixed(1)}%',
                  isShorter ? Colors.green : Colors.red,
                ),
                _buildComparisonStat(
                  'ขั้นตอนที่ตัดทอน (Eliminated)',
                  '${metrics.stepsEliminated} ขั้น',
                  'เดิม ${metrics.baselineProcess?.steps.length} ➜ ปัจจุบัน ${metrics.stepCount}',
                  metrics.stepsEliminated >= 0 ? Colors.green : Colors.orange,
                ),
                _buildComparisonStat(
                  'ประสิทธิภาพ PCE เพิ่มขึ้น',
                  '+${metrics.pceImprovementPercent.toStringAsFixed(1)}%',
                  'เดิม ${metrics.baselineProcess?.processCycleEfficiency.toStringAsFixed(1)}% ➜ ${metrics.processCycleEfficiency.toStringAsFixed(1)}%',
                  metrics.pceImprovementPercent >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonStat(String label, String value, String sub, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        Text(sub, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }

  Widget _buildAsmeBreakdownCard(LeanProcessMetrics metrics, ThemeData theme) {
    final total = metrics.totalDurationMinutes > 0 ? metrics.totalDurationMinutes : 1.0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'สัดส่วนกิจกรรม ASME (Process Symbols Breakdown)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...ProcessEventType.values.map((type) {
              final count = metrics.eventCounts[type] ?? 0;
              final duration = metrics.eventDurations[type] ?? 0.0;
              final ratio = (duration / total).clamp(0.0, 1.0);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(type.symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text(type.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Text(
                          '$count ขั้น | ${duration.toStringAsFixed(1)} นาที (${(ratio * 100).toStringAsFixed(1)}%)',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(type.color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildValueBreakdownCard(LeanProcessMetrics metrics, ThemeData theme) {
    final total = metrics.totalDurationMinutes > 0 ? metrics.totalDurationMinutes : 1.0;
    final vaRatio = (metrics.vaDurationMinutes / total).clamp(0.0, 1.0);
    final nnvaRatio = (metrics.nnvaDurationMinutes / total).clamp(0.0, 1.0);
    final nvaRatio = (metrics.nvaDurationMinutes / total).clamp(0.0, 1.0);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.donut_large_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'การจำแนกคุณค่า (Lean Value Ratio)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildValueProgressBar('จำเป็น / มีประโยชน์ (VA)', metrics.vaDurationMinutes, vaRatio, LeanValueType.va.color),
            const SizedBox(height: 12),
            _buildValueProgressBar('สูญเปล่าแต่จำเป็น (NNVA)', metrics.nnvaDurationMinutes, nnvaRatio, LeanValueType.nnva.color),
            const SizedBox(height: 12),
            _buildValueProgressBar('สูญเปล่าบริสุทธิ์ (NVA)', metrics.nvaDurationMinutes, nvaRatio, LeanValueType.nva.color),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'หลักการ Lean: ลดและกำจัด NVA ก่อน จากนั้นลดเวลา NNVA และปรับขั้นตอน VA ให้มีประสิทธิภาพสูงสุด (ECRS)',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueProgressBar(String label, double minutes, double ratio, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              '${minutes.toStringAsFixed(1)} นาที (${(ratio * 100).toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildWasteStepsMatrix(LeanProcessMetrics metrics, ThemeData theme) {
    final wastes = [...metrics.pureWasteSteps, ...metrics.necessaryWasteSteps];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'รายการขั้นตอนความสูญเปล่าที่ควรแก้ไข (${wastes.length} จุด)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (wastes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('ยอดเยี่ยม! ไม่พบขั้นตอนที่เป็นความสูญเปล่า (100% Value Added)'),
                ),
              )
            else
              ...wastes.map((step) {
                final isPureWaste = step.valueType == LeanValueType.nva;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isPureWaste
                        ? Colors.red.withValues(alpha: 0.06)
                        : Colors.amber.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isPureWaste
                          ? Colors.red.shade300
                          : Colors.amber.shade400,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: step.valueType.color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ขั้นที่ ${step.stepNo}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '[${step.eventType.symbol} ${step.eventType.label}] ${step.description}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Spacer(),
                                Text(
                                  'ใช้เวลา: ${step.durationMinutes} นาที | ระยะทาง: ${step.distanceMeters} ม.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (step.problemCause != null && step.problemCause!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '⚠️ ปัญหา/สาเหตุ: ${step.problemCause}',
                                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                              ),
                            ],
                            if (step.improvementIdea != null && step.improvementIdea!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '💡 ข้อเสนอแนะ ECRS: ${step.improvementIdea}',
                                style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.troubleshoot_rounded, color: Colors.deepOrange, size: 22),
                        tooltip: 'ทำ RCA 5-Why & ผังก้างปลา บนขั้นตอนนี้',
                        onPressed: () {
                          setState(() {
                            _rcaTargetStep = step;
                            _selectedTab = 2;
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildAiConsultantSection(
    LeanProcessMetrics metrics,
    AsyncValue<String?> aiState,
    ThemeData theme,
  ) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'ผู้ช่วยวิเคราะห์และปรับปรุง Lean ด้วย AI (AI Lean Consultant)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: aiState.isLoading
                      ? null
                      : () => ref
                          .read(aiLeanConsultantProvider.notifier)
                          .analyzeProcess(metrics.process),
                  icon: aiState.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.psychology_rounded, size: 18),
                  label: const Text('วิเคราะห์ ECRS ด้วย AI'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            aiState.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('กำลังวิเคราะห์ขั้นตอนงานและคำนวณข้อเสนอแนะ ECRS ตามหลัก Lean...'),
                    ],
                  ),
                ),
              ),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('เกิดข้อผิดพลาดในการวิเคราะห์ AI: $e', style: const TextStyle(color: Colors.red)),
              ),
              data: (markdown) {
                if (markdown == null || markdown.isEmpty) {
                  return Text(
                    'กดปุ่ม "วิเคราะห์ ECRS ด้วย AI" ด้านบน เพื่อให้ระบบ AI จำลองบทบาทเป็นวิศวกร Lean Consultant วิเคราะห์และเสนอแนะแนวทางลดเวลา ลดระยะทาง และกำจัดความสูญเปล่าให้อัตโนมัติ',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                  );
                }
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: SelectableText(
                    markdown,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
