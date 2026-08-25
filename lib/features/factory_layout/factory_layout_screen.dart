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
import '../../core/database/db_helper.dart';
import '../../core/theme/app_colors.dart';
import 'layout_pdf_service.dart';
import '../settings/settings_provider.dart';

final _machineSearchProvider = StateProvider<String>((ref) => '');
final _selectedMachinesProvider = StateProvider<Set<String>>((ref) => {});
final _isGridVisibleProvider = StateProvider<bool>((ref) => true);

extension ColorExtension on Color {
  String toHex() => '#${toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
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
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          // ESC behavior: Deselect machine and close any transient state
          ref.read(selectedMachineProvider.notifier).state = null;
          // If in Align mode, we stay in Align mode but could deselect?
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
            const Text('พื้นที่:', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Flexible(
              child: layoutList.when(
                data: (layouts) => DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isDense: true,
                    value: layouts.any((l) => l.layoutId == selectedLayoutId)
                        ? selectedLayoutId
                        : (layouts.isNotEmpty ? layouts.first.layoutId : null),
                    items: layouts
                        .map((l) => DropdownMenuItem(
                              value: l.layoutId,
                              child: Text(l.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ))
                        .toList(),
                    onChanged: (id) {
                      if (id != null) {
                        ref.read(selectedLayoutIdProvider.notifier).state = id;
                        ref.read(selectedMachineProvider.notifier).state = null;
                      }
                    },
                  ),
                ),
                loading: () => const SizedBox(width: 40, child: LinearProgressIndicator()),
                error: (error, stack) => const Icon(Icons.error_outline, size: 16),
              ),
            ),
          ],
        ),
        actions: [
          if (user?.isEngineerOrAbove ?? false)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: ElevatedButton.icon(
                icon: Icon(
                  isEditMode ? Icons.check_circle_outline_rounded : Icons.edit_location_alt_rounded,
                  size: 18,
                ),
                label: Text(
                  isEditMode ? 'เสร็จสิ้นการจัดวาง' : 'แก้ไขผังโรงงาน',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEditMode ? Colors.green.shade50 : Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: isEditMode ? Colors.green.shade700 : Theme.of(context).colorScheme.onPrimaryContainer,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  ref.read(isEditModeProvider.notifier).state = !isEditMode;
                  ref.read(isAligningModeProvider.notifier).state = false;
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
              final selectedLayoutId = ref.watch(selectedLayoutIdProvider);

              if (layouts.isEmpty) {
                return const Center(
                    child: Text('No factory layouts defined. Add an area to start.'));
              }
              
              if (layout == null) {
                if (selectedLayoutId != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Failed to load layout: $selectedLayoutId'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(currentLayoutProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                return const Center(child: Text('Select an area from the menu above.'));
              }

              final selectedMachine = ref.watch(selectedMachineProvider);

              return Row(
                children: [
                  // Main Canvas
                  Expanded(
                    flex: 3,
                    child: Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Consumer(
                        builder: (context, ref, child) {
                          final bgImageAsync = ref.watch(layoutBackgroundImageProvider(
                              layout.backgroundPath));
                          return FactoryLayoutCanvas(
                            layout: layout,
                            backgroundImage: bgImageAsync.valueOrNull,
                            selectedMachine: selectedMachine,
                            onMachineSelected: (machine) {
                              ref.read(selectedMachineProvider.notifier).state =
                                  machine;
                            },
                            isAligning: ref.watch(isAligningModeProvider),
                            showGrid: ref.watch(_isGridVisibleProvider),
                            tempBgScale: ref.watch(tempBgScaleProvider),
                            tempBgOffset: ref.watch(tempBgOffsetProvider),
                          );
                        },
                      ),
                    ),
                  ),
                  // Sidebar for details
                  if (selectedMachine != null)
                    Container(
                      width: 320,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                            left: BorderSide(
                                color: Theme.of(context).colorScheme.outlineVariant)),
                      ),
                      child: _MachineDetailPanel(machine: selectedMachine),
                    )
                  else
                    Container(
                      width: 320,
                      color: Theme.of(context).colorScheme.surface,
                      child: const Center(
                        child: Text(
                          'Click on a machine to see details',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
          // Floating Control Center (Zoom & Alignment)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: _LayoutControlBanner(
                layout: layoutAsync.valueOrNull,
                onAddMachine: (layout) => _showAddMachineMarkerDialog(context, ref, layout),
              ),
            ),
          ),
          // Scanning Overlay
          if (ref.watch(isScanningProvider))
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 24),
                    const Text('AI Scanning Floor Plan...',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Detecting zones and machine positions...',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
   );
  }
  void _showAddMachineMarkerDialog(BuildContext context, WidgetRef ref, FactoryLayout layout) {
    // Reset selection when opening dialog
    ref.read(_selectedMachinesProvider.notifier).state = {};
    double widthM = 3.0; // Default 3.0 meters
    double lengthM = 2.0; // Default 2.0 meters

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Consumer(
          builder: (context, ref, _) {
            final searchQuery = ref.watch(_machineSearchProvider);
            final selectedIds = ref.watch(_selectedMachinesProvider);
            final machinesAsync = ref.watch(machineListProvider(MachineListFilter(searchQuery: searchQuery)));

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_location_alt_rounded, color: AppColors.primary),
                  SizedBox(width: 12),
                  Text('วางเครื่องจักรลงผังโรงงาน'),
                ],
              ),
              content: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    Navigator.pop(context);
                  },
                },
                child: SizedBox(
                  width: 540,
                  height: 620,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dimension Configuration Box (กว้าง x ยาว คร่าวๆ)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.straighten_rounded, size: 16, color: AppColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  'ขนาดพื้นที่วางเครื่องจักรคร่าวๆ (กว้าง × ยาว)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: widthM.toStringAsFixed(1),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'ความกว้าง (Width)',
                                      suffixText: 'ม.',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) {
                                      final v = double.tryParse(val);
                                      if (v != null && v > 0) widthM = v;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: lengthM.toStringAsFixed(1),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'ความยาว (Length)',
                                      suffixText: 'ม.',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) {
                                      final v = double.tryParse(val);
                                      if (v != null && v > 0) lengthM = v;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                const Text('ขนาดมาตรฐาน:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                for (final preset in [
                                  {'label': '2.0 × 3.0 ม.', 'w': 2.0, 'h': 3.0},
                                  {'label': '2.5 × 4.0 ม.', 'w': 2.5, 'h': 4.0},
                                  {'label': '3.0 × 5.0 ม.', 'w': 3.0, 'h': 5.0},
                                  {'label': '4.0 × 6.0 ม.', 'w': 4.0, 'h': 6.0},
                                ]) ...[
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        widthM = preset['w'] as double;
                                        lengthM = preset['h'] as double;
                                      });
                                    },
                                    child: Chip(
                                      label: Text(preset['label'] as String, style: const TextStyle(fontSize: 10.5)),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: (widthM == preset['w'] && lengthM == preset['h'])
                                          ? Theme.of(context).colorScheme.primaryContainer
                                          : null,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Machine Search
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'ค้นหา รหัส หรือ ชื่อเครื่องจักร...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          isDense: true,
                        ),
                        onChanged: (v) => ref.read(_machineSearchProvider.notifier).state = v,
                      ),
                      const SizedBox(height: 10),

                      // Machine List
                      Expanded(
                        child: machinesAsync.when(
                          data: (machines) {
                            // Filter out machines already on this layout AND machines not yet approved
                            final placedIds = layout.machines.map((m) => m.machineId).toSet();
                            final available = machines.where((m) => 
                              !placedIds.contains(m.machineId) && 
                              m.stage3Status == HandoverStatus.approved
                            ).toList();
    
                            if (available.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.withAlpha(100)),
                                    const SizedBox(height: 16),
                                    const Text('ไม่พบเครื่องจักรที่อนุมัติแล้ว (Approved) หรือยังไม่ได้ลงผัง', 
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              );
                            }
    
                            return ListView.separated(
                              itemCount: available.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final m = available[index];
                                final isSelected = selectedIds.contains(m.machineId);
    
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: m.status.color.withAlpha(40),
                                    child: Text(m.machineNo.characters.take(1).toString(), 
                                        style: TextStyle(color: m.status.color, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(m.machineNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(m.machineName ?? '-'),
                                  trailing: Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      final current = Set<String>.from(ref.read(_selectedMachinesProvider));
                                      if (val == true) {
                                        current.add(m.machineId!);
                                      } else {
                                        current.remove(m.machineId);
                                      }
                                      ref.read(_selectedMachinesProvider.notifier).state = current;
                                    },
                                  ),
                                  onTap: () {
                                    final current = Set<String>.from(ref.read(_selectedMachinesProvider));
                                    if (isSelected) {
                                      current.remove(m.machineId);
                                    } else {
                                      current.add(m.machineId!);
                                    }
                                    ref.read(_selectedMachinesProvider.notifier).state = current;
                                  },
                                );
                              },
                            );
                          },
                          loading: () => const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('กำลังดึงข้อมูลจาก Registry...'),
                              ],
                            ),
                          ),
                          error: (err, _) => Center(child: Text('Error: $err')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
                FilledButton.icon(
                  icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                  onPressed: selectedIds.isEmpty ? null : () async {
                    final centerX = layout.canvasSize.width / 2;
                    final centerY = layout.canvasSize.height / 2;
                    
                    final machines = machinesAsync.valueOrNull ?? [];
                    final boxW = (widthM * 50.0).clamp(30.0, 600.0);
                    final boxH = (lengthM * 50.0).clamp(30.0, 600.0);
                    
                    int offsetIdx = 0;
                    for (final mid in selectedIds) {
                      final m = machines.firstWhere((element) => element.machineId == mid);
                      final positionId = 'pos_${mid}_${DateTime.now().millisecondsSinceEpoch}';
                      final posX = centerX + (offsetIdx * 40.0) - ((selectedIds.length - 1) * 20.0);
                      final posY = centerY + (offsetIdx * 30.0) - ((selectedIds.length - 1) * 15.0);
                      offsetIdx++;

                      await DbHelper.execute(
                        '''INSERT INTO machine_positions (
                             position_id, layout_id, machine_id, 
                             x_position, y_position, width, height, status_color
                           ) VALUES (@pid, @lid, @mid_param, @x, @y, @w, @h, @color)''',
                        params: {
                          'pid': positionId,
                          'lid': layout.layoutId,
                          'mid_param': mid,
                          'x': posX,
                          'y': posY,
                          'w': boxW,
                          'h': boxH,
                          'color': m.status.color.toHex(),
                        },
                      );
                    }

                    ref.invalidate(currentLayoutProvider);
                    ref.invalidate(dashboardStatsProvider);
                    if (context.mounted) Navigator.pop(context);
                  },
                  label: Text('วางลงผัง (${selectedIds.length} เครื่อง)'),
                ),
              ],
            );
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
  final bool isAligning;
  final bool showGrid;
  final double tempBgScale;
  final Offset tempBgOffset;

  const FactoryLayoutCanvas({
    super.key,
    required this.layout,
    this.backgroundImage,
    required this.selectedMachine,
    required this.onMachineSelected,
    this.isAligning = false,
    this.showGrid = true,
    this.tempBgScale = 1.0,
    this.tempBgOffset = Offset.zero,
  });

  @override
  ConsumerState<FactoryLayoutCanvas> createState() => _FactoryLayoutCanvasState();
}

class _FactoryLayoutCanvasState extends ConsumerState<FactoryLayoutCanvas> {
  MachinePosition? _draggedMachine;
  Offset? _dragStartOffset;

  Rect _getImageRect() {
    Rect imageRect = Rect.fromLTWH(0, 0, widget.layout.canvasSize.width, widget.layout.canvasSize.height);
    
    if (widget.backgroundImage != null) {
      final double imgWidth = widget.backgroundImage!.width.toDouble();
      final double imgHeight = widget.backgroundImage!.height.toDouble();
      final double canvasWidth = widget.layout.canvasSize.width;
      final double canvasHeight = widget.layout.canvasSize.height;

      final double imgAspect = imgWidth / imgHeight;
      final double canvasAspect = canvasWidth / canvasHeight;

      double drawWidth, drawHeight;
      double offsetX = 0, offsetY = 0;

      if (imgAspect > canvasAspect) {
        drawWidth = canvasWidth;
        drawHeight = canvasWidth / imgAspect;
        offsetY = (canvasHeight - drawHeight) / 2;
      } else {
        drawHeight = canvasHeight;
        drawWidth = canvasHeight * imgAspect;
        offsetX = (canvasWidth - drawWidth) / 2;
      }
      imageRect = Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
    }
    return imageRect;
  }

  Offset _toCanvasPoint(Offset localPoint, Offset panOffset, double zoomLevel, Rect imageRect) {
    // [OPTIONAL] If we want (0,0) to be the top-left of the image:
    // return ((localPoint - panOffset) / zoomLevel) - imageRect.topLeft;
    
    // For now, we remain compatible with standard canvas coordinates (1600x1000)
    // but the helper remains for future precision scaling.
    return (localPoint - panOffset) / zoomLevel;
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = ref.watch(isEditModeProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);
    final panOffset = ref.watch(panOffsetProvider);
    final imageRect = _getImageRect();

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final zoomFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
          final double newZoom = (zoomLevel * zoomFactor).clamp(0.1, 5.0);
          
          if (newZoom != zoomLevel) {
            final focusPoint = event.localPosition;
            final newOffset = focusPoint - (focusPoint - panOffset) * (newZoom / zoomLevel);
            
            ref.read(zoomLevelProvider.notifier).state = newZoom;
            ref.read(panOffsetProvider.notifier).state = newOffset;
          }
        }
      },
      child: GestureDetector(
        onScaleStart: (details) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localPoint = box.globalToLocal(details.focalPoint);
          final canvasPoint = _toCanvasPoint(localPoint, panOffset, zoomLevel, imageRect);

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
          final isAligning = ref.read(isAligningModeProvider);
          
          if (isAligning) {
            if (details.pointerCount == 1) {
              if (_dragStartOffset != null) {
                final delta = (details.localFocalPoint - _dragStartOffset!) / zoomLevel;
                ref.read(tempBgOffsetProvider.notifier).state += delta;
                _dragStartOffset = details.localFocalPoint;
              }
            } else if (details.pointerCount == 2) {
              ref.read(tempBgScaleProvider.notifier).state *= details.scale;
            }
            return;
          }

          if (isEditMode && _draggedMachine != null) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final localPoint = box.globalToLocal(details.focalPoint);
            final canvasPoint = _toCanvasPoint(localPoint, panOffset, zoomLevel, imageRect);
            
            setState(() {
              _draggedMachine = _draggedMachine!.copyWith(
                position: canvasPoint - (_dragStartOffset ?? Offset.zero),
              );
            });
            return;
          }

          if (details.pointerCount == 1) {
            if (_dragStartOffset != null) {
              final delta = details.localFocalPoint - _dragStartOffset!;
              ref.read(panOffsetProvider.notifier).state += delta;
              _dragStartOffset = details.localFocalPoint;
            }
          } else if (details.pointerCount == 2) {
            final double newZoom = (zoomLevel * details.scale).clamp(0.1, 5.0);
            ref.read(zoomLevelProvider.notifier).state = newZoom;
          }
        },
        onScaleEnd: (details) async {
          if (isEditMode && _draggedMachine != null) {
            await ref.read(layoutRepositoryProvider).updateMachinePosition(
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
          final canvasPoint = _toCanvasPoint(localPoint, panOffset, zoomLevel, imageRect);

          final machine = widget.layout.getMachineAt(canvasPoint);
          if (machine != null) {
            widget.onMachineSelected(machine);
          }
        },
        child: ClipRect(
          child: CustomPaint(
            size: Size.infinite,
            painter: FactoryLayoutPainter(
              layout: _draggedMachine != null 
                ? widget.layout.copyWith(
                    machines: widget.layout.machines.map((m) => 
                      m.machineId == _draggedMachine!.machineId ? _draggedMachine! : m
                    ).toList()
                  )
                : widget.layout,
              backgroundImage: widget.backgroundImage,
              zoomLevel: zoomLevel,
              offset: panOffset,
              selectedMachine: widget.selectedMachine,
              isAligning: widget.isAligning,
              showGrid: widget.showGrid,
              tempBgScale: widget.tempBgScale,
              tempBgOffset: widget.tempBgOffset,
              themeColors: {
                'backgroundColor': Theme.of(context).colorScheme.surface,
                'gridColor': Theme.of(context).colorScheme.outlineVariant.withAlpha(50),
                'labelColor': Theme.of(context).colorScheme.onSurface,
                'selectedBorderColor': Theme.of(context).colorScheme.primary,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel showing details of selected machine
class _MachineDetailPanel extends ConsumerWidget {
  final MachinePosition machine;

  const _MachineDetailPanel({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullMachineAsync = ref.watch(singleMachineProvider(machine.machineId));
    String? imagePath;
    
    if (fullMachineAsync.hasValue && fullMachineAsync.value != null) {
      final attachments = fullMachineAsync.value!.attachments;
      for (final att in attachments) {
        final path = att['file_path'] as String?;
        if (path != null) {
          final lower = path.toLowerCase();
          if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp')) {
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
          // Machine Image
          if (imagePath != null)
            Container(
              width: double.infinity,
              height: 160,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                ),
              ),
            ),

          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: machine.status.color.withAlpha(200),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              machine.status.label,
              style: TextStyle(
                color: machine.status.color.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Machine number
          _DetailRow(label: 'หมายเลขเครื่อง', value: machine.machineNo),

          // Brand and model
          if (machine.brand != null || machine.model != null)
            _DetailRow(
              label: 'รุ่น/แบรนด์',
              value: [
                machine.brand,
                machine.model,
              ].whereType<String>().join(' '),
            ),

          // Zone
          _DetailRow(label: 'โซน', value: machine.zoneId),

          // Dimensions (กว้าง x ยาว)
          _DetailRow(
            label: 'ขนาดพื้นที่เครื่องจักร (กว้าง × ยาว)',
            value:
                '${(machine.size.width / 50.0).toStringAsFixed(1)} ม. × ${(machine.size.height / 50.0).toStringAsFixed(1)} ม. (${machine.size.width.toInt()} × ${machine.size.height.toInt()} px)',
          ),

          // Position
          _DetailRow(
            label: 'ตำแหน่ง (พิกัด)',
            value:
                '(${machine.position.dx.toStringAsFixed(0)}, ${machine.position.dy.toStringAsFixed(0)})',
          ),

          // Last updated
          if (machine.lastUpdated != null)
            _DetailRow(
              label: 'อัปเดตล่าสุด',
              value: _formatDate(machine.lastUpdated!),
            ),

          const SizedBox(height: 16),

          // Edit Dimensions Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.aspect_ratio_rounded, size: 18),
              label: const Text('ปรับขนาด กว้าง × ยาว'),
              onPressed: () {
                _showEditMachineDimensionDialog(context, ref, machine);
              },
            ),
          ),
          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('บันทึกเป็น PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.withAlpha(20),
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

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('View Full Details'),
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
              label: const Text('View History'),
              onPressed: () {
                context.go('/work-orders?machineId=${machine.machineId}');
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('นำเครื่องจักรออกจากผัง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withAlpha(20),
                foregroundColor: Colors.red,
                elevation: 0,
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('ยืนยันนำออกจากผัง'),
                    content: Text('ต้องการนำเครื่องจักร ${machine.machineNo} ออกจากผังโรงงานนี้หรือไม่?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(context, true), 
                        child: const Text('นำออก'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await ref.read(layoutRepositoryProvider).deleteMachinePosition(
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

  void _showEditMachineDimensionDialog(BuildContext context, WidgetRef ref, MachinePosition machine) {
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
              Text('เครื่องจักร: ${machine.machineNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              const Text('เลือกขนาดมาตรฐานเร็ว:', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final preset in [
                    {'label': '2.0 × 3.0 ม.', 'w': 2.0, 'h': 3.0},
                    {'label': '2.5 × 4.0 ม.', 'w': 2.5, 'h': 4.0},
                    {'label': '3.0 × 5.0 ม.', 'w': 3.0, 'h': 5.0},
                    {'label': '4.0 × 6.0 ม.', 'w': 4.0, 'h': 6.0},
                  ]) ...[
                    InkWell(
                      onTap: () {
                        wCtrl.text = (preset['w'] as double).toStringAsFixed(1);
                        hCtrl.text = (preset['h'] as double).toStringAsFixed(1);
                      },
                      child: Chip(
                        label: Text(preset['label'] as String, style: const TextStyle(fontSize: 10.5)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              final newW = (double.tryParse(wCtrl.text.trim()) ?? currentWidthM) * 50.0;
              final newH = (double.tryParse(hCtrl.text.trim()) ?? currentLengthM) * 50.0;
              final newSize = Size(newW.clamp(30.0, 600.0), newH.clamp(30.0, 600.0));

              await ref.read(layoutRepositoryProvider).updateMachineSize(
                ref.read(selectedLayoutIdProvider)!,
                machine.machineId,
                newSize,
              );
              ref.invalidate(currentLayoutProvider);
              ref.read(selectedMachineProvider.notifier).state = machine.copyWith(size: newSize);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('บันทึกขนาด'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Simple detail row widget
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
class _LayoutControlBanner extends ConsumerWidget {
  final FactoryLayout? layout;
  final Function(FactoryLayout)? onAddMachine;

  const _LayoutControlBanner({this.layout, this.onAddMachine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (layout == null) return const SizedBox.shrink();
    final currentLayout = layout!; // Local promotion

    final isGridVisible = ref.watch(_isGridVisibleProvider);
    final isAligning = ref.watch(isAligningModeProvider);
    final isEditMode = ref.watch(isEditModeProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);
    final tempBgScale = ref.watch(tempBgScaleProvider);
    final tempBgOffset = ref.watch(tempBgOffsetProvider);
    final user = ref.watch(authProvider);

    return Card(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      color: Theme.of(context).colorScheme.surface.withAlpha(250),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Direct Add Machine Button
              if (user?.isEngineerOrAbove ?? false) ...[
                FilledButton.icon(
                  onPressed: onAddMachine != null ? () => onAddMachine!(currentLayout) : null,
                  icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                  label: const Text('วางเครื่องจักร', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
                const VerticalDivider(width: 20, indent: 8, endIndent: 8),
              ],

              // Zoom Group
              IconButton(
                icon: const Icon(Icons.zoom_out_rounded, size: 20),
                onPressed: () => ref.read(zoomLevelProvider.notifier).state = (zoomLevel * 0.8).clamp(0.5, 3.0),
                tooltip: 'ซูมออก',
              ),
              Text('${(zoomLevel * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.zoom_in_rounded, size: 20),
                onPressed: () => ref.read(zoomLevelProvider.notifier).state = (zoomLevel * 1.2).clamp(0.5, 3.0),
                tooltip: 'ซูมเข้า',
              ),
              const VerticalDivider(width: 20, indent: 8, endIndent: 8),
              
              // Reset View
              IconButton(
                icon: const Icon(Icons.center_focus_strong_rounded, size: 20),
                onPressed: () {
                  ref.read(zoomLevelProvider.notifier).state = 1.0;
                  ref.read(panOffsetProvider.notifier).state = Offset.zero;
                },
                tooltip: 'รีเซ็ตมุมมอง',
              ),

              if (user?.isEngineerOrAbove ?? false) ...[
                const VerticalDivider(width: 20, indent: 8, endIndent: 8),
                // Align Toggle
                IconButton(
                  icon: Icon(
                    Icons.straighten_rounded,
                    color: isAligning ? AppColors.primary : null,
                  ),
                  tooltip: 'จัดตำแหน่งผัง (Align Mode)',
                  onPressed: () {
                    if (!isAligning) {
                      ref.read(tempBgScaleProvider.notifier).state = layout?.backgroundScale ?? 1.0;
                      ref.read(tempBgOffsetProvider.notifier).state = layout?.backgroundOffset ?? Offset.zero;
                      ref.read(isEditModeProvider.notifier).state = false;
                    }
                    ref.read(isAligningModeProvider.notifier).state = !isAligning;
                  },
                ),
              ],

              if (isAligning) ...[
                const VerticalDivider(width: 20, indent: 8, endIndent: 8),
                // Precision Scaling Buttons (ย่อขยาย)
                _ToolButton(
                  icon: Icons.unfold_more_rounded,
                  tooltip: 'Fit Width (ย่อขยายตามแนวขวาง)',
                  onPressed: () async {
                    final bgImage = await ref.read(layoutBackgroundImageProvider(layout!.backgroundPath).future);
                    if (bgImage != null) {
                      final newScale = layout!.canvasSize.width / bgImage.width.toDouble();
                      ref.read(tempBgScaleProvider.notifier).state = newScale;
                    }
                  },
                ),
                _ToolButton(
                  icon: Icons.unfold_less_rounded,
                  tooltip: 'Fit Height (ย่อขยายตามแนวตั้ง)',
                  onPressed: () async {
                    final bgImage = await ref.read(layoutBackgroundImageProvider(layout!.backgroundPath).future);
                    if (bgImage != null) {
                      final newScale = layout!.canvasSize.height / bgImage.height.toDouble();
                      ref.read(tempBgScaleProvider.notifier).state = newScale;
                    }
                  },
                ),
                _ToolButton(
                  icon: Icons.center_focus_weak_rounded,
                  tooltip: 'วางกึ่งกลาง (Center Image)',
                  onPressed: () => ref.read(tempBgOffsetProvider.notifier).state = Offset.zero,
                ),
                const VerticalDivider(width: 20, indent: 8, endIndent: 8),
                // Save/Approve Action
                ElevatedButton(
                  onPressed: () async {
                    await ref.read(layoutRepositoryProvider).approveLayout(layout!.layoutId);
                    await ref.read(layoutRepositoryProvider).updateBackgroundAlignment(
                      layout!.layoutId,
                      tempBgScale,
                      tempBgOffset,
                    );
                    ref.read(isAligningModeProvider.notifier).state = false;
                    ref.invalidate(currentLayoutProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ผังได้รับการอนุมัติแล้ว')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    elevation: 0,
                  ),
                  child: const Text('บันทึกและอนุมัติ', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => ref.read(isAligningModeProvider.notifier).state = false,
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.redAccent)),
                ),
              ],

              // Management Actions (Visible in Edit Mode when not aligning)
              if (!isAligning && isEditMode) ...[
                const VerticalDivider(width: 20, indent: 8, endIndent: 8),
                ElevatedButton.icon(
                  onPressed: (currentLayout.isApproved) 
                    ? () => onAddMachine?.call(currentLayout)
                    : null,
                  icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                  label: Text(currentLayout.isApproved ? 'วางเครื่องจักร' : 'ต้องอนุมัติก่อน', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withAlpha(40),
                    foregroundColor: Colors.orange[900],
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              const VerticalDivider(width: 20, indent: 8, endIndent: 8),
              
              // Grid Toggle & Scale Note
              _ToolButton(
                icon: isGridVisible ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                tooltip: 'แสดงตารางกริด',
                onPressed: () => ref.read(_isGridVisibleProvider.notifier).state = !isGridVisible,
              ),
              const SizedBox(width: 4),
              const Text('1 ช่อง = 5x5ม.', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
    );
  }
}
