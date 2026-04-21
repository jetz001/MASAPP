import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'layout_models.dart';
import 'layout_painter.dart';
import 'layout_provider.dart';
import '../auth/auth_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../machine_intake/machine_models.dart';
import '../dashboard/dashboard_screen.dart';
import '../../core/database/db_helper.dart';
import '../../core/theme/app_colors.dart';

final _machineSearchProvider = StateProvider<String>((ref) => '');

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
    final zoomLevel = ref.watch(zoomLevelProvider);
    final layoutList = ref.watch(layoutListProvider);
    final selectedLayoutId = ref.watch(selectedLayoutIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Layout:'),
            const SizedBox(width: 12),
            layoutList.when(
              data: (layouts) => DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: layouts.any((l) => l.layoutId == selectedLayoutId)
                      ? selectedLayoutId
                      : (layouts.isNotEmpty ? layouts.first.layoutId : null),
                  items: layouts
                      .map((l) => DropdownMenuItem(
                            value: l.layoutId,
                            child: Text(l.name, style: const TextStyle(fontSize: 16)),
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
              loading: () => const SizedBox(
                  width: 100,
                  height: 20,
                  child: LinearProgressIndicator(minHeight: 2)),
              error: (error, stack) => const Text('Error loading layouts'),
            ),
          ],
        ),
        actions: [
          // Zoom controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SizedBox(
                width: 120,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.zoom_out_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 20),
                      onPressed: () {
                        ref.read(zoomLevelProvider.notifier).state =
                            (zoomLevel * 0.8).clamp(0.5, 3.0);
                      },
                      tooltip: 'Zoom Out',
                    ),
                    Text(
                      '${(zoomLevel * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.zoom_in_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 20),
                      onPressed: () {
                        ref.read(zoomLevelProvider.notifier).state =
                            (zoomLevel * 1.2).clamp(0.5, 3.0);
                      },
                      tooltip: 'Zoom In',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Reset view button
          IconButton(
            icon: Icon(Icons.center_focus_strong_rounded,
                color: Theme.of(context).colorScheme.onSurface, size: 20),
            onPressed: () {
              ref.read(zoomLevelProvider.notifier).state = 1.0;
              ref.read(panOffsetProvider.notifier).state = Offset.zero;
            },
            tooltip: 'Reset View',
          ),
          // Layout Management Button (Registry)
          IconButton(
            icon: const Icon(Icons.settings_suggest_rounded, color: AppColors.primary),
            tooltip: 'จัดการพื้นที่ (Manage Areas)',
            onPressed: () => context.go('/factory-layout/management'),
          ),
          // Edit Mode Toggle (Role-restricted)
          if (user?.isEngineerOrAbove ?? false)
            IconButton(
              icon: Icon(
                isEditMode ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                color: isEditMode ? Colors.orange : Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: isEditMode ? 'Exit Management Mode' : 'Enter Management Mode',
              onPressed: () {
                ref.read(isEditModeProvider.notifier).state = !isEditMode;
                // De-select machine when entering edit mode to avoid confusion
                ref.read(selectedMachineProvider.notifier).state = null;
              },
            ),
          const VerticalDivider(width: 1, indent: 12, endIndent: 12),
          if (isEditMode)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: ElevatedButton.icon(
                onPressed: () => _showAddMachineMarkerDialog(context, ref, layoutAsync.valueOrNull!),
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text('Add Machine'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withAlpha(40),
                  foregroundColor: Colors.orange[900],
                  elevation: 0,
                ),
              ),
            ),
          // Add Layout Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Area'),
              onPressed: () => _showAddLayoutDialog(context, ref),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
    );
  }
  void _showAddMachineMarkerDialog(BuildContext context, WidgetRef ref, FactoryLayout layout) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final searchQuery = ref.watch(_machineSearchProvider);
          final machinesAsync = ref.watch(machineListProvider(MachineListFilter(searchQuery: searchQuery)));

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.add_location_alt_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                const Text('เลือกเครื่องจักรลงผัง (From Registry)'),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 600,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ค้นหา รหัส หรือ ชื่อเครื่องจักร...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    onChanged: (v) => ref.read(_machineSearchProvider.notifier).state = v,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: machinesAsync.when(
                      data: (machines) {
                        // Filter out machines already on this layout
                        final placedIds = layout.machines.map((m) => m.machineId).toSet();
                        final available = machines.where((m) => !placedIds.contains(m.machineId)).toList();

                        if (available.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.withAlpha(100)),
                                const SizedBox(height: 16),
                                const Text('ไม่พบเครื่องจักรอื่นที่ยังไม่ได้ลงผัง', 
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
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: m.status.color.withAlpha(40),
                                child: Text(m.machineNo.characters.take(1).toString(), 
                                    style: TextStyle(color: m.status.color, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(m.machineNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(m.machineName ?? '-'),
                              trailing: const Icon(Icons.chevron_right, size: 16),
                              onTap: () async {
                                final centerX = layout.canvasSize.width / 2;
                                final centerY = layout.canvasSize.height / 2;
                                final positionId = 'pos_${DateTime.now().millisecondsSinceEpoch}';

                                await DbHelper.execute(
                                  '''INSERT INTO machine_positions (
                                       position_id, layout_id, machine_id, 
                                       x_position, y_position, width, height, status_color
                                     ) VALUES (@pid, @lid, @mid, @x, @y, @w, @h, @color)''',
                                  params: {
                                    'pid': positionId,
                                    'lid': layout.layoutId,
                                    'mid': m.machineId,
                                    'x': centerX,
                                    'y': centerY,
                                    'w': 60.0,
                                    'h': 50.0,
                                    'color': m.status.color.toHex(),
                                  },
                                );

                                ref.invalidate(currentLayoutProvider);
                                ref.invalidate(dashboardStatsProvider);
                                if (context.mounted) Navigator.pop(context);
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
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ],
          );
        },
      ),
    );
  }

  void _showAddLayoutDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    String? selectedFilePath;
    String? selectedFileName;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Factory Area'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Area Name',
                    hintText: 'e.g., Assembly Line A, Warehouse 1',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                // Dimensions removed as requested - will be calculated from file
                const SizedBox(height: 24),
                // Background Picker
                const Text('Floor Plan Background (Optional)', 
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  child: Column(
                    children: [
                      if (selectedFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.file_present_rounded, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(selectedFileName!, 
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(() {
                                  selectedFilePath = null;
                                  selectedFileName = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(selectedFileName == null ? 'Select PDF or Image' : 'Change File'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                            );
                            if (result != null && result.files.single.path != null) {
                              setState(() {
                                selectedFilePath = result.files.single.path;
                                selectedFileName = result.files.single.name;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;

                final repo = ref.read(layoutRepositoryProvider);
                final user = ref.read(authProvider);

                String? finalBgPath;
                const double widthM = 32.0; // Fixed default
                const double heightM = 20.0; // Fixed default

                if (selectedFilePath != null) {
                  // Copy file to app directory
                  final appDir = await getApplicationDocumentsDirectory();
                  final layoutsDir = Directory(p.join(appDir.path, 'layouts'));
                  if (!await layoutsDir.exists()) await layoutsDir.create();
                  
                  final extension = p.extension(selectedFilePath!);
                  final newFileName = 'bg_${DateTime.now().millisecondsSinceEpoch}$extension';
                  final targetPath = p.join(layoutsDir.path, newFileName);
                  
                  await File(selectedFilePath!).copy(targetPath);
                  finalBgPath = targetPath;
                }
                
                final id = await repo.createLayout(
                  name: nameCtrl.text,
                  widthM: widthM,
                  heightM: heightM,
                  backgroundPath: finalBgPath,
                  createdBy: user?.userId,
                );

                ref.invalidate(layoutListProvider);
                ref.read(selectedLayoutIdProvider.notifier).state = id;
                ref.read(selectedMachineProvider.notifier).state = null;

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created area: ${nameCtrl.text} (${widthM.toStringAsFixed(1)}m x ${heightM.toStringAsFixed(1)}m)')),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
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

  const FactoryLayoutCanvas({
    super.key,
    required this.layout,
    this.backgroundImage,
    required this.selectedMachine,
    required this.onMachineSelected,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _DetailRow(label: 'Machine No', value: machine.machineNo),

          // Brand and model
          if (machine.brand != null || machine.model != null)
            _DetailRow(
              label: 'Model',
              value: [
                machine.brand,
                machine.model,
              ].whereType<String>().join(' '),
            ),

          // Zone
          _DetailRow(label: 'Zone', value: machine.zoneId),

          // Position
          _DetailRow(
            label: 'Position',
            value:
                '(${machine.position.dx.toStringAsFixed(0)}, ${machine.position.dy.toStringAsFixed(0)})',
          ),

          // Last updated
          if (machine.lastUpdated != null)
            _DetailRow(
              label: 'Updated',
              value: _formatDate(machine.lastUpdated!),
            ),

          const SizedBox(height: 24),

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
          if (ref.watch(isEditModeProvider)) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Remove Marker'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withAlpha(20),
                  foregroundColor: Colors.red,
                  elevation: 0,
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Remove Marker'),
                      content: Text('Remove ${machine.machineNo} from this layout?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(context, true), 
                          child: const Text('Remove'),
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
