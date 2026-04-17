import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'layout_models.dart';
import 'layout_painter.dart';
import 'layout_provider.dart';

class FactoryLayoutScreen extends ConsumerStatefulWidget {
  const FactoryLayoutScreen({super.key});

  @override
  ConsumerState<FactoryLayoutScreen> createState() =>
      _FactoryLayoutScreenState();
}

class _FactoryLayoutScreenState extends ConsumerState<FactoryLayoutScreen> {
  @override
  Widget build(BuildContext context) {
    final layoutAsync = ref.watch(currentLayoutProvider);
    final selectedMachine = ref.watch(selectedMachineProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factory Layout'),
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
                      icon: const Icon(Icons.zoom_out),
                      onPressed: () {
                        ref.read(zoomLevelProvider.notifier).state =
                            (zoomLevel * 0.8).clamp(0.5, 3.0);
                      },
                      tooltip: 'Zoom Out',
                    ),
                    Text(
                      '${(zoomLevel * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_in),
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
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              ref.read(zoomLevelProvider.notifier).state = 1.0;
              ref.read(panOffsetProvider.notifier).state = Offset.zero;
            },
            tooltip: 'Reset View',
          ),
        ],
      ),
      body: layoutAsync.when(
        data: (layout) {
          if (layout == null) {
            return const Center(child: Text('Layout not found'));
          }

          return Row(
            children: [
              // Main layout canvas
              Expanded(
                flex: 3,
                child: Container(
                  color: const Color(0xFF1F2937),
                  child: FactoryLayoutCanvas(
                    layout: layout,
                    selectedMachine: selectedMachine,
                    onMachineSelected: (machine) {
                      ref.read(selectedMachineProvider.notifier).state =
                          machine;
                    },
                  ),
                ),
              ),
              // Right sidebar with machine details
              Expanded(
                flex: 1,
                child: Container(
                  color: const Color(0xFF111827),
                  child: selectedMachine == null
                      ? const Center(
                          child: Text(
                            'Click on a machine to see details',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : _MachineDetailPanel(machine: selectedMachine),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

/// Panel showing details of selected machine
class _MachineDetailPanel extends StatelessWidget {
  final MachinePosition machine;

  const _MachineDetailPanel({required this.machine});

  @override
  Widget build(BuildContext context) {
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
              style: const TextStyle(
                color: Colors.white,
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

          // Action buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('View Full Details'),
              onPressed: () {
                // Navigate to machine detail screen
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.history, size: 18),
              label: const Text('View History'),
              onPressed: () {
                // Show machine history/maintenance records
              },
            ),
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
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
