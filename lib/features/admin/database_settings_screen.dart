import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'database_settings_provider.dart';

class DatabaseSettingsScreen extends ConsumerStatefulWidget {
  const DatabaseSettingsScreen({super.key});

  @override
  ConsumerState<DatabaseSettingsScreen> createState() =>
      _DatabaseSettingsScreenState();
}

class _DatabaseSettingsScreenState
    extends ConsumerState<DatabaseSettingsScreen> {
  late TextEditingController _dbPathController;
  late TextEditingController _sharedFolderController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    _dbPathController = TextEditingController(text: config.dbPath);
    _sharedFolderController = TextEditingController(
      text: config.sharedFolderPath ?? '',
    );
  }

  @override
  void dispose() {
    _dbPathController.dispose();
    _sharedFolderController.dispose();
    super.dispose();
  }

  Future<void> _pickDatabaseFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite'],
        dialogTitle: 'Select or create database file',
      );

      if (result != null) {
        _dbPathController.text = result.files.single.path!;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _pickSharedFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select shared folder for documents',
      );

      if (result != null) {
        _sharedFolderController.text = result;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _saveConfiguration() async {
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(appConfigProvider.notifier);
      final dbPathSuccess = await notifier.updateDbPath(_dbPathController.text);

      if (!dbPathSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to database at this path'),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      if (_sharedFolderController.text.isNotEmpty) {
        final folderSuccess = await notifier.updateSharedFolderPath(
          _sharedFolderController.text,
        );
        if (!folderSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Shared folder path is invalid')),
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(appConfigProvider.notifier);
      final result = await notifier.createBackup();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result
                  ? 'Backup created successfully'
                  : 'Failed to create backup',
            ),
          ),
        );
        // Refresh backups list
        ref.invalidate(recentBackupsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final backupsAsync = ref.watch(recentBackupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Database Configuration'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Database Path Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Database Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'For LAN deployment, use a network path (e.g., \\\\192.168.1.50\\MaintenanceApp\\db.sqlite)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _dbPathController,
                      decoration: InputDecoration(
                        labelText: 'Database File Path',
                        hintText:
                            'C:\\path\\to\\database.db or \\\\server\\share\\database.db',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: _pickDatabaseFile,
                        ),
                      ),
                      readOnly: false,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current: ${config.dbPath}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Shared Folder Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shared Folder for Documents',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Location for PDFs, drawings, and shared files (optional)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _sharedFolderController,
                      decoration: InputDecoration(
                        labelText: 'Shared Folder Path',
                        hintText:
                            '\\\\server\\share\\MaintenanceApp\\documents',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: _pickSharedFolder,
                        ),
                      ),
                      readOnly: false,
                    ),
                    const SizedBox(height: 8),
                    if (config.sharedFolderPath != null)
                      Text(
                        'Current: ${config.sharedFolderPath}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveConfiguration,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save Configuration'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Backup Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Database Backups',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _createBackup,
                        icon: const Icon(Icons.backup),
                        label: const Text('Create Backup Now'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Recent Backups',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    backupsAsync.when(
                      data: (backups) {
                        if (backups.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No backups yet',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: backups.length,
                          itemBuilder: (context, index) {
                            final backup = backups[index];
                            final dateFormat = DateFormat(
                              'yyyy-MM-dd HH:mm:ss',
                            );
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.backup_table, size: 20),
                              title: Text(
                                backup.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateFormat.format(backup.modifiedAt),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    '${backup.sizeMB.toStringAsFixed(2)} MB',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(),
                      ),
                      error: (err, stack) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Error loading backups: $err',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
