import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'add_station_dialog.dart';
import 'line_balancing_provider.dart';

class LineGraphCanvas extends ConsumerStatefulWidget {
  const LineGraphCanvas({super.key});

  @override
  ConsumerState<LineGraphCanvas> createState() => _LineGraphCanvasState();
}

class _LineGraphCanvasState extends ConsumerState<LineGraphCanvas> {
  String? _linkingFromId;

  static const double nodeWidth = 260;
  static const double nodeHeight = 150;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lineBalancingProvider);
    final notifier = ref.read(lineBalancingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Controls & Status Toolbar
        _buildToolbar(context, state, notifier, isDark),

        // 2. Main Static Flow View
        Expanded(
          child: _buildStaticFlowView(context, state, notifier, theme, isDark),
        ),
      ],
    );
  }

  // ================= 1. TOP TOOLBAR =================
  Widget _buildToolbar(
    BuildContext context,
    LineBalancingState state,
    LineBalancingNotifier notifier,
    bool isDark,
  ) {
    final linkingStation =
        state.stations.where((s) => s.id == _linkingFromId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F23) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 8,
        children: [
          // Left: View title badge & Quick Add button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_timeline_outlined,
                        size: 16, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Text(
                      'ผังกระบวนการผลิต (Static Flow)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  final lastStation = state.stations.lastOrNull;
                  final nextPos = lastStation != null
                      ? Offset(
                          lastStation.position.dx + 360,
                          lastStation.position.dy,
                        )
                      : Offset.zero;
                  showDialog(
                    context: context,
                    builder: (_) => AddStationDialog(
                      notifier: notifier,
                      fromStationId: lastStation?.id,
                      suggestedPosition: nextPos,
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label:
                    const Text('เพิ่มสถานีงาน', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),

          // Center/Right: Linking Banner or Quick Stats
          if (_linkingFromId != null && linkingStation != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link, size: 16, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text(
                    '⚡ กำลังโยงสายจาก: ${linkingStation.name} (คลิกสถานีปลายทางที่ต้องการต่อ)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color:
                          isDark ? Colors.amberAccent : Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _linkingFromId = null),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        'ยกเลิก',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatPill(
                  icon: Icons.precision_manufacturing_outlined,
                  label: '${state.stations.length} สถานี',
                  color: Colors.blueAccent,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildStatPill(
                  icon: Icons.timer_outlined,
                  label:
                      'CT รวม: ${state.totalCycleTime.toStringAsFixed(1)}s (${(state.totalCycleTime / 60).toStringAsFixed(1)}m)',
                  color: Colors.teal,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildStatPill(
                  icon: Icons.people_outline_rounded,
                  label: 'พนักงาน: ${state.totalWorkers} คน',
                  color: Colors.purpleAccent,
                  isDark: isDark,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ================= 2. STATIC FLOW VIEW =================
  Widget _buildStaticFlowView(
    BuildContext context,
    LineBalancingState state,
    LineBalancingNotifier notifier,
    ThemeData theme,
    bool isDark,
  ) {
    if (state.stations.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1E1E24) : Colors.white)
                .withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.precision_manufacturing_outlined,
                  size: 56, color: Colors.blue.shade400),
              const SizedBox(height: 16),
              Text(
                'ยังไม่มีสถานีงานในสายการผลิตนี้',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'กดปุ่ม "เพิ่มสถานีแรก" เพื่อเริ่มสร้างผังขั้นตอนการผลิต',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AddStationDialog(notifier: notifier),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มสถานีแรก'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: isDark ? const Color(0xFF131316) : const Color(0xFFF1F5F9),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ...state.stations.asMap().entries.expand((entry) {
                final i = entry.key;
                final station = entry.value;
                final nextStation = i < state.stations.length - 1
                    ? state.stations[i + 1]
                    : null;
                final isLinking = _linkingFromId == station.id;
                final isLinkTarget =
                    _linkingFromId != null && _linkingFromId != station.id;

                final items = <Widget>[
                  // 1. Station Card (Static / Solid)
                  GestureDetector(
                    onTap: () {
                      if (_linkingFromId != null &&
                          _linkingFromId != station.id) {
                        notifier.linkStations(
                          _linkingFromId!,
                          station.id,
                        );
                        setState(() => _linkingFromId = null);
                      }
                    },
                    onDoubleTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AddStationDialog(
                          notifier: notifier,
                          initialStation: station,
                        ),
                      );
                    },
                    child: _buildStationCard(
                      station,
                      i,
                      isLinking,
                      isLinkTarget,
                      state,
                      notifier,
                      theme,
                      isDark,
                    ),
                  ),
                ];

                // 2. Flow Connector & WIP Buffer between Station i and Station i+1
                if (i < state.stations.length - 1 && nextStation != null) {
                  items.add(
                    _buildStaticFlowConnector(
                      fromSt: station,
                      toSt: nextStation,
                      state: state,
                      notifier: notifier,
                      theme: theme,
                      isDark: isDark,
                    ),
                  );
                }

                return items;
              }),

              // 3. Add Next Station Button at end of sequence
              const SizedBox(width: 24),
              _buildStaticAddStationButton(
                  context, notifier, state.stations.lastOrNull, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaticFlowConnector({
    required WorkstationData fromSt,
    required WorkstationData toSt,
    required LineBalancingState state,
    required LineBalancingNotifier notifier,
    required ThemeData theme,
    required bool isDark,
  }) {
    final connId = '${fromSt.id}->${toSt.id}';
    final conn = state.resolvedConnections
        .where((c) => c.id == connId)
        .firstOrNull;
    final wireColor =
        conn != null ? Color(conn.colorValue) : const Color(0xFFFB8C00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Arrow Line (──➔)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 3,
                decoration: BoxDecoration(
                  color: wireColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 20, color: wireColor),
            ],
          ),
          const SizedBox(height: 8),
          // WIP Buffer (▽ WIP: X ชิ้น)
          _buildWipBufferBadge(
            context,
            conn ??
                LineConnection(
                  id: connId,
                  fromStationId: fromSt.id,
                  toStationId: toSt.id,
                  colorValue: wireColor.toARGB32(),
                ),
            fromSt,
            toSt,
            notifier,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStaticAddStationButton(
    BuildContext context,
    LineBalancingNotifier notifier,
    WorkstationData? lastStation,
    bool isDark,
  ) {
    return InkWell(
      onTap: () {
        final nextPos = lastStation != null
            ? Offset(lastStation.position.dx + 360, lastStation.position.dy)
            : Offset.zero;
        showDialog(
          context: context,
          builder: (_) => AddStationDialog(
            notifier: notifier,
            fromStationId: lastStation?.id,
            suggestedPosition: nextPos,
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 170,
        height: nodeHeight,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF27272A).withValues(alpha: 0.5)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded,
                  size: 24, color: Colors.blueAccent),
            ),
            const SizedBox(height: 8),
            const Text(
              'เพิ่มสถานีถัดไป',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              lastStation != null
                  ? 'ต่อจาก ${lastStation.name}'
                  : 'เริ่มผังการผลิต',
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationCard(
    WorkstationData station,
    int stationIndex,
    bool isLinking,
    bool isLinkTarget,
    LineBalancingState state,
    LineBalancingNotifier notifier,
    ThemeData theme,
    bool isDark,
  ) {
    // Smart extraction of Machine / Station Code (e.g. GM01, GM03)
    String displayCode = '';
    String displayTitle = station.name;

    final bracketMatch = RegExp(r'\[(.*?)\]').firstMatch(station.name);
    if (bracketMatch != null) {
      displayCode = bracketMatch.group(1)!.trim();
      displayTitle = station.name.replaceAll(bracketMatch.group(0)!, '').trim();
    } else {
      final codePrefixMatch =
          RegExp(r'^([A-Za-z0-9\-_]+)\s*[:\-–]?\s*(.*)$')
              .firstMatch(station.name);
      if (codePrefixMatch != null && codePrefixMatch.group(1)!.length <= 8) {
        displayCode = codePrefixMatch.group(1)!.trim();
        final rest = codePrefixMatch.group(2)?.trim() ?? '';
        if (rest.isNotEmpty) displayTitle = rest;
      } else {
        displayCode = 'GM${(stationIndex + 1).toString().padLeft(2, '0')}';
      }
    }

    if (displayTitle.isEmpty &&
        station.machineName != null &&
        station.machineName!.isNotEmpty) {
      displayTitle = station.machineName!;
    }

    final headerBg = isDark
        ? const Color(0xFF27272A)
        : (isLinkTarget
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : const Color(0xFFF1F5F9));
    final bodyBg = isDark ? const Color(0xFF18181B) : Colors.white;
    final borderColor = isLinking
        ? Colors.amberAccent
        : (isLinkTarget
            ? theme.colorScheme.primary
            : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFCBD5E1)));

    return Material(
      elevation: isLinking ? 12 : 5,
      borderRadius: BorderRadius.circular(10),
      color: Colors.transparent,
      child: Container(
        width: nodeWidth,
        constraints: const BoxConstraints(minHeight: nodeHeight),
        decoration: BoxDecoration(
          color: bodyBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: isLinking ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: isLinking ? 12 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ================= TOP HEADER BOX (GM01) =================
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? const Color(0xFF3F3F46)
                          : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Station Code (Bold GM01)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        displayCode,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.cyanAccent
                              : theme.colorScheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Title / Machine Name
                    Expanded(
                      child: Text(
                        displayTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Edit Button
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AddStationDialog(
                            notifier: notifier,
                            initialStation: station,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: Icon(Icons.edit_outlined,
                            size: 15, color: Colors.grey.shade400),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Delete Button
                    InkWell(
                      onTap: () => notifier.removeStation(station.id),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: Icon(Icons.close_rounded,
                            size: 15, color: Colors.red.shade400),
                      ),
                    ),
                  ],
                ),
              ),

              // ================= BOTTOM BODY 2-COLUMN TABLE (CT | M) =================
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ----- LEFT COLUMN: CT (Cycle Time) -----
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'CT',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.blue.shade400,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('—',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${station.cycleTime.toStringAsFixed(1)} s',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '(${(station.cycleTime / 60).toStringAsFixed(1)} min)',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Vertical Table Divider Line
                      Container(
                        width: 1.2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE2E8F0),
                      ),

                      // ----- RIGHT COLUMN: M (Manpower / Workers) -----
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'M',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.teal.shade400,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('—',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${station.workers} คน',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${station.valueType.toUpperCase()}${station.waitingTimeSec > 0 ? ' (W: ${station.waitingTimeSec.toInt()}s)' : ''}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: station.valueType == 'va'
                                    ? Colors.green.shade600
                                    : Colors.orange.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ================= LOOP-BACK / BRANCH BADGES =================
              if (station.nextStationIds.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF222227)
                        : const Color(0xFFF1F5F9),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? const Color(0xFF2E2E34)
                            : const Color(0xFFE2E8F0),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    children: station.nextStationIds.map((nextId) {
                      final nextSt = state.stations
                          .where((s) => s.id == nextId)
                          .firstOrNull;
                      if (nextSt == null) return const SizedBox.shrink();
                      final nextIdx =
                          state.stations.indexWhere((s) => s.id == nextId);
                      final isLoopBack =
                          nextIdx != -1 && nextIdx <= stationIndex;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isLoopBack
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isLoopBack
                                ? Colors.amber.withValues(alpha: 0.5)
                                : Colors.blue.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLoopBack
                                  ? Icons.replay_rounded
                                  : Icons.trending_flat_rounded,
                              size: 11,
                              color: isLoopBack
                                  ? Colors.amber
                                  : Colors.blueAccent,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isLoopBack
                                  ? 'วนกลับ: ${nextSt.name}'
                                  : 'ต่อไปยัง: ${nextSt.name}',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isLoopBack
                                    ? (isDark
                                        ? Colors.amberAccent
                                        : Colors.amber.shade900)
                                    : (isDark
                                        ? Colors.cyanAccent
                                        : Colors.blue.shade800),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              // ================= FOOTER CONNECTOR / QUICK ACTIONS =================
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1F1F23)
                      : const Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? const Color(0xFF2E2E34)
                          : const Color(0xFFF1F5F9),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Link Mode Button
                    InkWell(
                      onTap: () {
                        setState(() {
                          _linkingFromId = isLinking ? null : station.id;
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLinking
                              ? Colors.amber.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLinking ? Icons.close : Icons.link,
                              size: 13,
                              color: isLinking
                                  ? Colors.amberAccent
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              isLinking ? 'ยกเลิก' : 'โยงสาย',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isLinking
                                    ? Colors.amberAccent
                                    : Colors.grey.shade400,
                                fontWeight: isLinking
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Arrow -> Quick Add Next Station Button ([+] button)
                    Tooltip(
                      message:
                          'เพิ่มสถานีถัดไปต่อจากสถานีนี้ (Quick Add Next Station)',
                      child: InkWell(
                        onTap: () {
                          final nextPos = Offset(
                              station.position.dx + 360, station.position.dy);
                          showDialog(
                            context: context,
                            builder: (_) => AddStationDialog(
                              notifier: notifier,
                              fromStationId: station.id,
                              suggestedPosition: nextPos,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.4),
                                width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '➔',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 3),
                              Icon(Icons.add,
                                  size: 13, color: Colors.blueAccent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= WIP / BUFFER BADGE (VSM ▽ Inventory Box) =================
  Widget _buildWipBufferBadge(
    BuildContext context,
    LineConnection conn,
    WorkstationData fromSt,
    WorkstationData toSt,
    LineBalancingNotifier notifier,
    bool isDark,
  ) {
    final wipQty = toSt.bufferQuantity;
    final wireColor = Color(conn.colorValue);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: wireColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inverted Triangle (IE / VSM WIP Inventory Symbol ▽)
          InkWell(
            onTap: () => _showWipEditDialog(context, toSt, notifier),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '▽',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.amber,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  wipQty > 0 ? '$wipQty ชิ้น' : 'WIP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 14,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          const SizedBox(width: 2),
          // Plus Button to insert intermediate station
          Tooltip(
            message: 'แทรกสถานีงานตรงนี้ (Insert Station)',
            child: InkWell(
              onTap: () {
                final insertPos = Offset(
                  (fromSt.position.dx + toSt.position.dx) / 2,
                  (fromSt.position.dy + toSt.position.dy) / 2,
                );
                showDialog(
                  context: context,
                  builder: (_) => AddStationDialog(
                    notifier: notifier,
                    fromStationId: fromSt.id,
                    suggestedPosition: insertPos,
                  ),
                );
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: isDark ? Colors.tealAccent : Colors.teal.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWipEditDialog(
    BuildContext context,
    WorkstationData targetStation,
    LineBalancingNotifier notifier,
  ) {
    final bufferController =
        TextEditingController(text: targetStation.bufferQuantity.toString());
    final waitController = TextEditingController(
        text: targetStation.waitingTimeSec.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Text('▽ ',
                style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
            Text('ตั้งค่าสต็อกระหว่างกระบวนการ (WIP Buffer)'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('สถานีปลายทาง: ${targetStation.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: bufferController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'จำนวนสต็อก WIP พักรอ (ชิ้น / ชิ้นงาน)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  suffixText: 'ชิ้น',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: waitController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'เวลารอคอยก่อนเข้าสถานี (Waiting Time)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer_outlined),
                  suffixText: 'วินาที',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              final buf = int.tryParse(bufferController.text.trim()) ??
                  targetStation.bufferQuantity;
              final wt = double.tryParse(waitController.text.trim()) ??
                  targetStation.waitingTimeSec;
              notifier.updateStation(
                targetStation.id,
                targetStation.name,
                targetStation.cycleTime,
                machineId: targetStation.machineId,
                machineName: targetStation.machineName,
                workers: targetStation.workers,
                laborCost: targetStation.laborCost,
                energyCost: targetStation.energyCost,
                materialCost: targetStation.materialCost,
                otherCost: targetStation.otherCost,
                waitingTimeSec: wt,
                bufferQuantity: buf,
              );
              Navigator.pop(ctx);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}
