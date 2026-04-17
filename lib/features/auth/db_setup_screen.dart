import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/database/db_connection.dart';
import '../../core/database/db_helper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// First-launch screen for selecting or creating a shared SQLite database file.
class DbSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onConnected;
  const DbSetupScreen({super.key, required this.onConnected});

  @override
  ConsumerState<DbSetupScreen> createState() => _DbSetupScreenState();
}

class _DbSetupScreenState extends ConsumerState<DbSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pathCtrl = TextEditingController();

  bool _loading = false;
  String? _statusMessage;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    _initDefaultPath();
  }

  Future<void> _initDefaultPath() async {
    final defaults = await AppConfig.createDefault();
    _pathCtrl.text = defaults.dbPath;
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      dialogTitle: 'เลือกไฟล์ฐานข้อมูล MASAPP',
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _pathCtrl.text = result.files.single.path!;
      });
    }
  }

  Future<void> _selectFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'เลือกโฟลเดอร์สำหรับสร้างฐานข้อมูลใหม่',
    );

    if (result != null) {
      setState(() {
        _pathCtrl.text = '$result\\masapp.db';
      });
    }
  }

  Future<void> _testAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    final path = _pathCtrl.text.trim();
    final file = File(path);
    final exists = await file.exists();
    if (!mounted) return;

    final config = AppConfig(dbPath: path);
    bool needsInit = !exists;

    if (exists) {
      // Check if it's an empty database
      try {
        await DbConnection.instance.connect(config);
        final tables = await DbHelper.query(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
        );
        if (tables.isEmpty) {
          needsInit = true;
        }
      } catch (_) {
        needsInit = true; // Something is wrong, maybe try to init
      }
    }

    if (needsInit) {
      if (!mounted) return;
      // Show confirmation to create or initialize DB
      final create =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                !exists ? 'ไม่พบไฟล์ฐานข้อมูล' : 'ตั้งค่าฐานข้อมูลใหม่',
              ),
              content: Text(
                !exists
                    ? 'ต้องการสร้างไฟล์ฐานข้อมูลใหม่ที่\n$path หรือไม่?'
                    : 'ไฟล์นี้มีอยู่แล้ว คุณต้องการ "ล้างข้อมูลเดิม" และลงโครงสร้างใหม่ (Initialize) หรือไม่?\n\n*คำเตือน: ข้อมูลเดิมทั้งหมดจะถูกลบทิ้ง',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: exists ? Colors.orange : null,
                  ),
                  child: Text(
                    !exists ? 'สร้างไฟล์ใหม่' : 'ล้างข้อมูลและเริ่มใหม่',
                  ),
                ),
              ],
            ),
          ) ??
          false;

      if (!create) {
        setState(() => _loading = false);
        return;
      }

      try {
        // Create directory if not exists
        final dir = file.parent;
        if (!await dir.exists()) await dir.create(recursive: true);

        // Connect (creates the file)
        await DbConnection.instance.connect(config);

        // Initialize Schema & Seed
        final schema = await rootBundle.loadString('db/schema_sqlite.sql');
        final seed = await rootBundle.loadString('db/seed_sqlite.sql');

        final statements = [...schema.split(';'), ...seed.split(';')];

        Logger().d('[Setup] Executing ${statements.length} statements...');
        int executed = 0;
        await DbHelper.transaction((txn) async {
          for (var s in statements) {
            final trimmed = s.trim();
            if (trimmed.isNotEmpty) {
              try {
                await txn.execute(trimmed);
                executed++;
              } catch (e) {
                Logger().e('[Setup] SQL Error on statement: "$trimmed"');
                Logger().e('[Setup] Error details: $e');
                rethrow; // Ensure transaction rolls back
              }
            }
          }
        });
        Logger().i('[Setup] Successfully executed $executed statements.');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ตั้งค่าข้อมูลเริ่มต้นสำเร็จแล้ว (ล้างของเก่าออกแล้ว)',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        Logger().e('[Setup] Error during init: $e');
        setState(() {
          _statusOk = false;
          _statusMessage = 'เกิดข้อผิดพลาดในการสร้างฐานข้อมูล: $e';
          _loading = false;
        });
        return;
      }
    }

    // Double check connection
    final ok = await DbConnection.instance.testConnection(config);
    if (!mounted) return;

    if (ok) {
      await AppConfigService.save(config);
      await DbConnection.instance.connect(config);
      setState(() {
        _statusOk = true;
        _statusMessage = 'เชื่อมต่อฐานข้อมูลสำเร็จ!';
        _loading = false;
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        widget.onConnected();
      }
    } else {
      setState(() {
        _statusOk = false;
        _statusMessage =
            'ไม่สามารถเปิดไฟล์ฐานข้อมูลได้ กรุณาตรวจสอบสิทธิ์การเข้าถึง';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 550,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.folder_shared_rounded,
                              color: AppColors.primary,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ตั้งค่าฐานข้อมูล (Shared Offline)',
                                  style: AppTextStyles.headlineMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'เลือกไฟล์ฐานข้อมูล (.db) จากโฟลเดอร์ที่แชร์กันในวง LAN',
                                  style: AppTextStyles.secondary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

                      Text(
                        'ที่อยู่ไฟล์ฐานข้อมูล (.db)',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pathCtrl,
                              style: AppTextStyles.bodyMedium,
                              decoration: const InputDecoration(
                                hintText: 'C:\\Shared\\masapp.db',
                                prefixIcon: Icon(Icons.description_outlined),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'กรุณาเลือกหรือระบุที่อยู่ไฟล์'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.search),
                            label: const Text('เลือกไฟล์'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _selectFolder,
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('สร้างไฟล์ใหม่ในโฟลเดอร์...'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Info box
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'หากต้องการใช้ร่วมกันหลายเครื่อง ให้เลือกไฟล์ที่อยู่ใน Network Drive หรือโฟลเดอร์ที่แชร์ไว้',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_statusMessage != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _statusOk
                                ? AppColors.successContainer
                                : AppColors.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _statusOk
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusOk ? Icons.check_circle : Icons.error,
                                color: _statusOk
                                    ? AppColors.success
                                    : AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: _statusOk
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _testAndSave,
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'บันทึกและเริ่มต้นใช้งาน',
                                  style: TextStyle(fontSize: 18),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
