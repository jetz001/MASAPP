import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'layout_models.dart';
import 'layout_painter.dart';
import 'layout_provider.dart';
import '../auth/auth_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../machine_intake/machine_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../../core/theme/app_colors.dart';
import 'layout_pdf_service.dart';
import '../settings/settings_provider.dart';

final _machineSearchProvider = StateProvider<String>((ref) => '');
final _isGridVisibleProvider = StateProvider<bool>((ref) => true);

extension ColorExtension on Color {
  String toHex() =>
      '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

class FactoryLayoutScreen extends ConsumerStatefulWidget {
  const FactoryLayoutScreen({super.key});

  @override
  ConsumerState<FactoryLayoutScreen> createState() =>
      _FactoryLayoutScreenState();
}

class _FactoryLayoutScreenState extends ConsumerState<FactoryLayoutScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Refresh machine status every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        ref.invalidate(currentLayoutProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isEditMode = ref.watch(isEditModeProvider);
    final layoutAsync = ref.watch(currentLayoutProvider);
    final layoutList = ref.watch(layoutListProvider);
    final selectedLayoutId = ref.watch(selectedLayoutIdProvider);

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          ref.read(selectedMachineProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.go('/factory-layout/management'),
            tooltip: 'กลับสู่ ทะเบียนพื้นที่โรงงาน',
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('พื้นที่:',
                  style: TextStyle(fontSize: 15, color: Colors.grey)),
              const SizedBox(width: 8),
              Flexible(
                child: layoutList.when(
                  data: (layouts) => DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isDense: true,
                      value: layouts.any((l) => l.layoutId == selectedLayoutId)
                          ? selectedLayoutId
                          : (layouts.isNotEmpty
                              ? layouts.first.layoutId
                              : null),
                      items: layouts
                          .map((l) => DropdownMenuItem(
                                value: l.layoutId,
                                child: Text(l.name,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ))
                          .toList(),
                      onChanged: (id) {
                        if (id != null) {
                          ref.read(selectedLayoutIdProvider.notifier).state =
                              id;
                          ref.read(selectedMachineProvider.notifier).state =
                              null;
                        }
                      },
                    ),
                  ),
                  loading: () => const SizedBox(
                      width: 40, child: LinearProgressIndicator()),
                  error: (error, stack) =>
                      const Icon(Icons.error_outline, size: 16),
                ),
              ),
            ],
          ),
          actions: [
            // Print / Export PDF Button
            IconButton(
              icon: const Icon(Icons.print_rounded, size: 20),
              tooltip: 'พิมพ์รายงานพื้นที่ (PDF)',
              onPressed: () async {
                final layouts = layoutList.valueOrNull ?? [];
                final settings = ref.read(appSettingsProvider).valueOrNull;
                final user = ref.read(authProvider);
                if (layouts.isNotEmpty && settings != null) {
                  await LayoutPdfService.generateAreaRegistryPdf(
                    layouts: layouts,
                    settings: settings,
                    userName: user?.fullName ?? 'System User',
                  );
                }
              },
            ),
            const SizedBox(width: 4),

            // Mode Indicator / Toggle Button
            if (user?.isEngineerOrAbove ?? false)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: FilledButton.icon(
                  icon: Icon(
                    isEditMode
                        ? Icons.check_circle_rounded
                        : Icons.edit_location_alt_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isEditMode ? 'เสร็จสิ้นการจัดวาง' : 'จัดวางเครื่องจักร',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isEditMode
                        ? Colors.green.shade600
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    ref.read(isEditModeProvider.notifier).state = !isEditMode;
                    ref.read(selectedMachineProvider.notifier).state = null;
                  },
                ),
              ),
            const SizedBox(width: 12),
          ],
        ),
        body: Stack(
          children: [
            layoutAsync.when(
              data: (layout) {
                final layouts = layoutList.valueOrNull ?? [];
                if (layouts.isEmpty) {
                  return const Center(
                      child: Text(
                          'ยังไม่มีพื้นที่โรงงานในระบบ กรุณาสร้างพื้นที่ก่อน'));
                }

                if (layout == null) {
                  return const Center(
                      child: Text('กรุณาเลือกพื้นที่จากเมนูด้านบน'));
                }

                final selectedMachine = ref.watch(selectedMachineProvider);

                return Row(
                  children: [
                    // 1. Machine Placement Sidebar (When in Edit Mode)
                    if (isEditMode)
                      _MachineSidebar(
                        layout: layout,
                      ),

                    // 2. Main Auto-Fit Canvas View
                    Expanded(
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Consumer(
                          builder: (context, ref, child) {
                            final bgImageAsync = ref.watch(
                                layoutBackgroundImageProvider(
                                    layout.backgroundPath));
                            return FactoryLayoutCanvas(
                              layout: layout,
                              backgroundImage: bgImageAsync.valueOrNull,
                              selectedMachine: selectedMachine,
                              onMachineSelected: (machine) {
                                ref
                                    .read(selectedMachineProvider.notifier)
                                    .state = machine;
                              },
                              showGrid: ref.watch(_isGridVisibleProvider),
                            );
                          },
                        ),
                      ),
                    ),

                    // 3. Machine Detail Panel (When in View Mode & Machine Selected)
                    if (!isEditMode && selectedMachine != null)
                      Container(
                        width: 330,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                              left: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant)),
                        ),
                        child:
                            _MachineDetailPanel(machine: selectedMachine),
                      ),
                  ],
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),

            // Floating Zoom & View Controls Toolbar
            Positioned(
              bottom: 20,
              right: isEditMode ? 20 : (ref.watch(selectedMachineProvider) != null ? 350 : 20),
              child: _LayoutControlBanner(
                layout: layoutAsync.valueOrNull,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Machine Placement Sidebar (Drag & Drop or 1-Click placement)
class _MachineSidebar extends ConsumerWidget {
  final FactoryLayout layout;

  const _MachineSidebar({required this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(_machineSearchProvider);
    final machinesAsync = ref.watch(
        machineListProvider(MachineListFilter(searchQuery: searchQuery)));
    final placedIds = layout.machines.map((m) => m.machineId).toSet();

    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.25),
              border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      'ลากวางเครื่องจักรลงผัง',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'แตะค้างแล้วลากไปปล่อยบนผัง หรือกดปุ่ม (+)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ค้นหาเครื่องจักร...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (v) =>
                  ref.read(_machineSearchProvider.notifier).state = v,
            ),
          ),

          // Machines List
          Expanded(
            child: machinesAsync.when(
              data: (machines) {
                final available = machines.where((m) =>
                    !placedIds.contains(m.machineId) &&
                    m.stage3Status == HandoverStatus.approved).toList();

                if (available.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 40, color: Colors.green.shade400),
                          const SizedBox(height: 10),
                          const Text(
                            'วางเครื่องจักรทั้งหมดแล้ว\nหรือยังไม่มีเครื่องจักรใหม่',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  itemCount: available.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final m = available[index];
                    return _DraggableMachineCard(
                      machine: m,
                      layoutId: layout.layoutId,
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                  child: Text('Error: $err',
                      style: const TextStyle(fontSize: 12))),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draggable Machine Card Item in Sidebar
class _DraggableMachineCard extends ConsumerWidget {
  final MachineModel machine;
  final String layoutId;

  const _DraggableMachineCard({
    required this.machine,
    required this.layoutId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = machine.status.color;

    return Draggable<MachineModel>(
      data: machine,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(20),
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 4, backgroundColor: statusColor),
              const SizedBox(width: 6),
              Text(
                machine.machineNo,
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _buildCardContent(context, ref, statusColor),
      ),
      child: _buildCardContent(context, ref, statusColor),
    );
  }

  Widget _buildCardContent(
      BuildContext context, WidgetRef ref, Color statusColor) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Container(
          width: 10,
          height: 32,
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Text(
          machine.machineNo,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          machine.machineName ?? machine.model ?? '-',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded,
              size: 20, color: AppColors.primary),
          tooltip: 'วางลงกึ่งกลางผัง',
          onPressed: () async {
            final layout = ref.read(currentLayoutProvider).valueOrNull;
            if (layout != null) {
              final center = Offset(layout.canvasSize.width / 2,
                  layout.canvasSize.height / 2);
              await ref.read(layoutRepositoryProvider).addMachinePosition(
                    layoutId: layoutId,
                    machineId: machine.machineId!,
                    position: center,
                    statusColor: machine.status.color.toHex(),
                  );
              ref.invalidate(currentLayoutProvider);
              ref.invalidate(dashboardStatsProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('วางเครื่องจักร ${machine.machineNo} ลงบนผังแล้ว')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}

class FactoryLayoutCanvas extends ConsumerStatefulWidget {
  final FactoryLayout layout;
  final ui.Image? backgroundImage;
  final MachinePosition? selectedMachine;
  final Function(MachinePosition) onMachineSelected;
  final bool showGrid;

  const FactoryLayoutCanvas({
    super.key,
    required this.layout,
    this.backgroundImage,
    required this.selectedMachine,
    required this.onMachineSelected,
    this.showGrid = true,
  });

  @override
  ConsumerState<FactoryLayoutCanvas> createState() =>
      _FactoryLayoutCanvasState();
}

class _FactoryLayoutCanvasState extends ConsumerState<FactoryLayoutCanvas> {
  MachinePosition? _draggedMachine;
  Offset? _dragStartOffset;

  Offset _toCanvasPoint(Offset localPoint, Offset panOffset, double zoomLevel) {
    return (localPoint - panOffset) / zoomLevel;
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = ref.watch(isEditModeProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);
    final panOffset = ref.watch(panOffsetProvider);

    return DragTarget<MachineModel>(
      onAcceptWithDetails: (details) async {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPoint = box.globalToLocal(details.offset);
        final canvasPoint = _toCanvasPoint(localPoint, panOffset, zoomLevel);
        final machine = details.data;

        await ref.read(layoutRepositoryProvider).addMachinePosition(
              layoutId: widget.layout.layoutId,
              machineId: machine.machineId!,
              position: canvasPoint,
              statusColor: machine.status.color.toHex(),
            );

        ref.invalidate(currentLayoutProvider);
        ref.invalidate(dashboardStatsProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('วางเครื่องจักร ${machine.machineNo} ลงบนตำแหน่งแล้ว')),
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration: candidateData.isNotEmpty
              ? BoxDecoration(
                  border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.6), width: 3),
                )
              : null,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final zoomFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
                final double newZoom =
                    (zoomLevel * zoomFactor).clamp(0.2, 4.0);

                if (newZoom != zoomLevel) {
                  final focusPoint = event.localPosition;
                  final newOffset = focusPoint -
                      (focusPoint - panOffset) * (newZoom / zoomLevel);

                  ref.read(zoomLevelProvider.notifier).state = newZoom;
                  ref.read(panOffsetProvider.notifier).state = newOffset;
                }
              }
            },
            child: GestureDetector(
              onScaleStart: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final localPoint = box.globalToLocal(details.focalPoint);
                final canvasPoint =
                    _toCanvasPoint(localPoint, panOffset, zoomLevel);

                final machine = widget.layout.getMachineAt(canvasPoint);
                if (isEditMode && machine != null) {
                  setState(() {
                    _draggedMachine = machine;
                    _dragStartOffset = canvasPoint - machine.position;
                  });
                  widget.onMachineSelected(machine);
                } else {
                  _dragStartOffset = details.localFocalPoint;
                }
              },
              onScaleUpdate: (details) {
                if (isEditMode && _draggedMachine != null) {
                  final RenderBox box =
                      context.findRenderObject() as RenderBox;
                  final localPoint = box.globalToLocal(details.focalPoint);
                  final canvasPoint =
                      _toCanvasPoint(localPoint, panOffset, zoomLevel);

                  setState(() {
                    _draggedMachine = _draggedMachine!.copyWith(
                      position:
                          canvasPoint - (_dragStartOffset ?? Offset.zero),
                    );
                  });
                  return;
                }

                if (details.pointerCount == 1) {
                  if (_dragStartOffset != null) {
                    final delta =
                        details.localFocalPoint - _dragStartOffset!;
                    ref.read(panOffsetProvider.notifier).state += delta;
                    _dragStartOffset = details.localFocalPoint;
                  }
                } else if (details.pointerCount == 2) {
                  final double newZoom =
                      (zoomLevel * details.scale).clamp(0.2, 4.0);
                  ref.read(zoomLevelProvider.notifier).state = newZoom;
                }
              },
              onScaleEnd: (details) async {
                if (isEditMode && _draggedMachine != null) {
                  await ref
                      .read(layoutRepositoryProvider)
                      .updateMachinePosition(
                        widget.layout.layoutId,
                        _draggedMachine!.machineId,
                        _draggedMachine!.position,
                      );

                  setState(() {
                    _draggedMachine = null;
                    _dragStartOffset = null;
                  });
                  ref.invalidate(currentLayoutProvider);
                }
              },
              onTapUp: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final localPoint = box.globalToLocal(details.globalPosition);
                final canvasPoint =
                    _toCanvasPoint(localPoint, panOffset, zoomLevel);

                final machine = widget.layout.getMachineAt(canvasPoint);
                if (machine != null) {
                  widget.onMachineSelected(machine);
                } else {
                  // Click on empty canvas deselects
                  ref.read(selectedMachineProvider.notifier).state = null;
                }
              },
              child: ClipRect(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: FactoryLayoutPainter(
                    layout: _draggedMachine != null
                        ? widget.layout.copyWith(
                            machines: widget.layout.machines
                                .map((m) =>
                                    m.machineId == _draggedMachine!.machineId
                                        ? _draggedMachine!
                                        : m)
                                .toList(),
                          )
                        : widget.layout,
                    backgroundImage: widget.backgroundImage,
                    zoomLevel: zoomLevel,
                    offset: panOffset,
                    selectedMachine: widget.selectedMachine,
                    showGrid: widget.showGrid,
                    themeColors: {
                      'backgroundColor':
                          Theme.of(context).colorScheme.surface,
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Machine Details & Maintenance Information Panel
class _MachineDetailPanel extends ConsumerWidget {
  final MachinePosition machine;

  const _MachineDetailPanel({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullMachineAsync =
        ref.watch(singleMachineProvider(machine.machineId));
    String? imagePath;

    if (fullMachineAsync.hasValue && fullMachineAsync.value != null) {
      final attachments = fullMachineAsync.value!.attachments;
      for (final att in attachments) {
        final path = att['file_path'] as String?;
        if (path != null) {
          final lower = path.toLowerCase();
          if (lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.webp')) {
            imagePath = path;
            break;
          }
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ข้อมูลเครื่องจักรบนผัง',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  ref.read(selectedMachineProvider.notifier).state = null;
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Machine Image Box
          Container(
            width: double.infinity,
            height: 150,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: imagePath != null && File(imagePath).existsSync()
                ? Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildImagePlaceholder(context, machine),
                  )
                : _buildImagePlaceholder(context, machine),
          ),

          // Status indicator badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: machine.status.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: machine.status.color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 4, backgroundColor: machine.status.color),
                const SizedBox(width: 6),
                Text(
                  'สถานะ: ${machine.status.label}',
                  style: TextStyle(
                    color: machine.status.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _DetailRow(label: 'รหัสเครื่องจักร', value: machine.machineNo),
          if (machine.brand != null || machine.model != null)
            _DetailRow(
              label: 'รุ่น / ยี่ห้อ',
              value: [machine.brand, machine.model]
                  .whereType<String>()
                  .join(' '),
            ),
          _DetailRow(
            label: 'ขนาดเครื่องจักรบนผัง (กว้าง × ยาว)',
            value:
                '${(machine.size.width / 50.0).toStringAsFixed(1)} ม. × ${(machine.size.height / 50.0).toStringAsFixed(1)} ม.',
          ),
          _DetailRow(
            label: 'พิกัดตำแหน่งบนผัง',
            value:
                'X: ${machine.position.dx.toStringAsFixed(0)}, Y: ${machine.position.dy.toStringAsFixed(0)}',
          ),

          const SizedBox(height: 12),

          // Quick Resize Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.aspect_ratio_rounded, size: 18),
              label: const Text('ปรับขนาดเครื่องจักร (กว้าง × ยาว)'),
              onPressed: () {
                _showEditMachineDimensionDialog(context, ref, machine);
              },
            ),
          ),
          const SizedBox(height: 8),

          // Print Machine Location Map Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('พิมพ์'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                foregroundColor: AppColors.primary,
                elevation: 0,
              ),
              onPressed: () async {
                final layout = ref.read(currentLayoutProvider).value;
                final settings = ref.read(appSettingsProvider).valueOrNull;
                final user = ref.read(authProvider);
                if (layout != null && settings != null) {
                  await LayoutPdfService.generateMachineTag(
                    layout: layout,
                    machine: machine,
                    settings: settings,
                    userName: user?.fullName ?? 'System User',
                    imagePath: imagePath,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),

          // Quick Action Buttons
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('ดูทะเบียนเครื่องจักรแบบเต็ม'),
              onPressed: () {
                context.go('/machine-registry/${machine.machineId}');
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDocumentCode, size: 18),
              label: const Text('ประวัติการแจ้งซ่อม (Work Orders)'),
              onPressed: () {
                context.go('/work-orders?machineId=${machine.machineId}');
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),

          // Remove Machine from Layout
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_sweep_rounded,
                  size: 18, color: Colors.redAccent),
              label: const Text('นำเครื่องจักรออกจากผังนี้',
                  style: TextStyle(color: Colors.redAccent)),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('ยืนยันนำออกจากผัง'),
                    content: Text(
                        'ต้องการนำเครื่องจักร ${machine.machineNo} ออกจากผังพื้นที่นี้หรือไม่?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('ยกเลิก')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('นำออก'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await ref
                      .read(layoutRepositoryProvider)
                      .deleteMachinePosition(
                        ref.read(selectedLayoutIdProvider)!,
                        machine.positionId,
                      );
                  ref.invalidate(currentLayoutProvider);
                  ref.invalidate(dashboardStatsProvider);
                  ref.read(selectedMachineProvider.notifier).state = null;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEditMachineDimensionDialog(
      BuildContext context, WidgetRef ref, MachinePosition machine) {
    double currentWidthM = machine.size.width / 50.0;
    double currentLengthM = machine.size.height / 50.0;
    final wCtrl = TextEditingController(text: currentWidthM.toStringAsFixed(1));
    final hCtrl = TextEditingController(text: currentLengthM.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.aspect_ratio_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('ปรับขนาด ${machine.machineNo}'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('เครื่องจักร: ${machine.machineNo}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'ความกว้าง (Width)',
                        suffixText: 'ม.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: hCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'ความยาว (Length)',
                        suffixText: 'ม.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('เลือกขนาดมาตรฐานเร็ว:',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final preset in [
                    {'label': '2.0 × 3.0 ม.', 'w': 2.0, 'h': 3.0},
                    {'label': '2.5 × 3.5 ม.', 'w': 2.5, 'h': 3.5},
                    {'label': '3.0 × 5.0 ม.', 'w': 3.0, 'h': 5.0},
                    {'label': '4.0 × 6.0 ม.', 'w': 4.0, 'h': 6.0},
                  ]) ...[
                    InkWell(
                      onTap: () {
                        wCtrl.text = (preset['w'] as double).toStringAsFixed(1);
                        hCtrl.text = (preset['h'] as double).toStringAsFixed(1);
                      },
                      child: Chip(
                        label: Text(preset['label'] as String,
                            style: const TextStyle(fontSize: 10.5)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              final newW =
                  (double.tryParse(wCtrl.text.trim()) ?? currentWidthM) * 50.0;
              final newH =
                  (double.tryParse(hCtrl.text.trim()) ?? currentLengthM) * 50.0;
              final newSize =
                  Size(newW.clamp(30.0, 600.0), newH.clamp(30.0, 600.0));

              await ref.read(layoutRepositoryProvider).updateMachineSize(
                    ref.read(selectedLayoutIdProvider)!,
                    machine.machineId,
                    newSize,
                  );
              ref.invalidate(currentLayoutProvider);
              ref.read(selectedMachineProvider.notifier).state =
                  machine.copyWith(size: newSize);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('บันทึกขนาด'),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(
      BuildContext context, MachinePosition machine) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.precision_manufacturing_rounded,
              size: 42, color: Colors.grey.shade400),
          const SizedBox(height: 6),
          Text(
            machine.machineNo,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            machine.model ?? machine.brand ?? 'Machine',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Floating Zoom & View Controls Pill
class _LayoutControlBanner extends ConsumerWidget {
  final FactoryLayout? layout;

  const _LayoutControlBanner({this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (layout == null) return const SizedBox.shrink();

    final isGridVisible = ref.watch(_isGridVisibleProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);

    return Card(
      elevation: 6,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.zoom_out_rounded, size: 20),
              onPressed: () => ref.read(zoomLevelProvider.notifier).state =
                  (zoomLevel * 0.8).clamp(0.2, 4.0),
              tooltip: 'ซูมออก',
            ),
            Text(
              '${(zoomLevel * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in_rounded, size: 20),
              onPressed: () => ref.read(zoomLevelProvider.notifier).state =
                  (zoomLevel * 1.2).clamp(0.2, 4.0),
              tooltip: 'ซูมเข้า',
            ),
            const SizedBox(
              height: 20,
              child: VerticalDivider(width: 16),
            ),
            IconButton(
              icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
              onPressed: () {
                ref.read(zoomLevelProvider.notifier).state = 1.0;
                ref.read(panOffsetProvider.notifier).state = Offset.zero;
              },
              tooltip: 'รีเซ็ตมุมมอง (Center View)',
            ),
            IconButton(
              icon: Icon(
                isGridVisible
                    ? Icons.grid_on_rounded
                    : Icons.grid_off_rounded,
                size: 20,
                color: isGridVisible ? AppColors.primary : null,
              ),
              tooltip: 'แสดงตารางกริด',
              onPressed: () => ref
                  .read(_isGridVisibleProvider.notifier)
                  .state = !isGridVisible,
            ),
          ],
        ),
      ),
    );
  }
}
