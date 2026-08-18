import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/crypto_utils.dart';
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
  final _companyCtrl = TextEditingController();
  final _adminUsernameCtrl = TextEditingController(text: 'admin');
  final _adminPassCtrl = TextEditingController();
  final _serialKeyCtrl = TextEditingController();
  String? _logoBase64;

  bool _loading = false;
  bool _isCreatingNew = false;

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
    _companyCtrl.dispose();
    _adminUsernameCtrl.dispose();
    _adminPassCtrl.dispose();
    _serialKeyCtrl.dispose();
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

  Future<void> _pickLogo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _logoBase64 = base64Encode(bytes);
      });
    }
  }

  void _setFailure(String message) {
    if (!mounted) return;
    setState(() {
      _statusOk = false;
      _statusMessage = message;
      _loading = false;
    });
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

    if (!_isCreatingNew) {
      // Connect to existing
      if (!exists) {
        setState(() {
          _statusOk = false;
          _statusMessage =
              'ไม่พบไฟล์ฐานข้อมูลที่ระบุ กรุณาตรวจสอบเส้นทางอีกครั้ง';
          _loading = false;
        });
        return;
      }
    } else {
      // Creating new
      if (exists) {
        final create = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ตั้งค่าฐานข้อมูลใหม่'),
            content: const Text(
              'ไฟล์นี้มีอยู่แล้ว คุณต้องการ "ล้างข้อมูลเดิม" และลงโครงสร้างใหม่ (Initialize) หรือไม่?\n\n*คำเตือน: ข้อมูลเดิมทั้งหมดจะถูกลบทิ้ง',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('ล้างข้อมูลและเริ่มใหม่'),
              ),
            ],
          ),
        );
        if (create == null || !create) {
          setState(() => _loading = false);
          return;
        }
      }

      // Execute Initialization
      try {
        final dir = file.parent;
        if (!await dir.exists()) await dir.create(recursive: true);

        await DbConnection.instance.connect(config);

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
              }
            }
          }

          // Inject setup configurations
          final company = _companyCtrl.text.trim();
          if (company.isNotEmpty) {
            await txn.execute(
              "UPDATE app_settings SET setting_value = ? WHERE setting_key = 'app.company_name'",
              [company],
            );
          }
          final serial = _serialKeyCtrl.text.trim();
          if (serial.isNotEmpty) {
            await txn.execute(
              "INSERT INTO app_settings (setting_key, setting_value, description) VALUES ('app.serial_key', ?, 'Serial License Key')",
              [serial],
            );
          }
          if (_logoBase64 != null && _logoBase64!.isNotEmpty) {
            await txn.execute(
              "UPDATE app_settings SET setting_value = ? WHERE setting_key = 'org_logo'",
              [_logoBase64],
            );
          }
          final adminUser = _adminUsernameCtrl.text.trim();
          final adminPass = _adminPassCtrl.text;
          if (adminUser.isNotEmpty && adminPass.isNotEmpty) {
            final hashedPass = CryptoUtils.hashPassword(adminPass);
            await txn.execute(
              "UPDATE users SET username = ?, password_hash = ? WHERE role = 'admin'",
              [adminUser, hashedPass],
            );
          }
        });
        Logger().i('[Setup] Successfully executed $executed statements.');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ตั้งค่าข้อมูลเริ่มต้นสำเร็จ'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        Logger().e('[Setup] Error during init: $e');
        _setFailure('เกิดข้อผิดพลาดในการสร้างฐานข้อมูล: $e');
        return;
      }
    }

    // Double check connection
    try {
      final ok = await DbConnection.instance.testConnection(config);
      if (!mounted) return;

      if (!ok) {
        _setFailure(
          'ไม่สามารถเปิดไฟล์ฐานข้อมูลได้ กรุณาตรวจสอบสิทธิ์การเข้าถึง',
        );
        return;
      }

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
    } catch (e) {
      Logger().e('[Setup] Error while saving config or connecting DB: $e');
      _setFailure('บันทึกการตั้งค่าหรือเชื่อมต่อฐานข้อมูลไม่สำเร็จ: $e');
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
                      // --- Mode Selection ---
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _isCreatingNew = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: !_isCreatingNew
                                      ? AppColors.primary
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: !_isCreatingNew
                                        ? AppColors.primary
                                        : Colors.white24,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.link,
                                      color: !_isCreatingNew
                                          ? Colors.white
                                          : Colors.white54,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'เชื่อมต่อฐานข้อมูลเดิม',
                                      style: TextStyle(
                                        color: !_isCreatingNew
                                            ? Colors.white
                                            : Colors.white54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '(สำหรับเครื่องลูกข่าย)',
                                      style: TextStyle(
                                        color: !_isCreatingNew
                                            ? Colors.white70
                                            : Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _isCreatingNew = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: _isCreatingNew
                                      ? AppColors.primary
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _isCreatingNew
                                        ? AppColors.primary
                                        : Colors.white24,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.add_box,
                                      color: _isCreatingNew
                                          ? Colors.white
                                          : Colors.white54,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'สร้างฐานข้อมูลใหม่',
                                      style: TextStyle(
                                        color: _isCreatingNew
                                            ? Colors.white
                                            : Colors.white54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '(สำหรับลงครั้งแรก)',
                                      style: TextStyle(
                                        color: _isCreatingNew
                                            ? Colors.white70
                                            : Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // --- Path Selection (Always visible) ---
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
                              decoration: InputDecoration(
                                hintText: _isCreatingNew
                                    ? r'C:\MASAPP\masapp.db'
                                    : '\\\\SERVER\\Shared\\masapp.db',
                                prefixIcon: const Icon(
                                  Icons.description_outlined,
                                ),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'กรุณาเลือกหรือระบุที่อยู่ไฟล์'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _isCreatingNew
                                ? _selectFolder
                                : _pickFile,
                            icon: const Icon(Icons.folder_open),
                            label: Text(
                              _isCreatingNew ? 'เลือกโฟลเดอร์' : 'เลือกไฟล์',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // --- New Database Fields (Only visible if _isCreatingNew) ---
                      if (_isCreatingNew) ...[
                        Text(
                          'โลโก้บริษัท',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _pickLogo,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: _logoBase64 != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      base64Decode(_logoBase64!),
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo,
                                        color: Colors.white54,
                                        size: 32,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'เลือกโลโก้',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          'ชื่อบริษัท / องค์กร',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _companyCtrl,
                          style: AppTextStyles.bodyMedium,
                          decoration: const InputDecoration(
                            hintText: 'โรงงานตัวอย่าง จำกัด',
                            prefixIcon: Icon(Icons.business),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          'ชื่อผู้ใช้งาน Admin',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _adminUsernameCtrl,
                          style: AppTextStyles.bodyMedium,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (v) =>
                              _isCreatingNew && (v == null || v.isEmpty)
                              ? 'กรุณาระบุ Username'
                              : null,
                        ),
                        const SizedBox(height: 20),

                        Text(
                          'รหัสผ่าน Admin',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _adminPassCtrl,
                          style: AppTextStyles.bodyMedium,
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'ปล่อยว่างหากต้องการใช้รหัสผ่านตั้งต้น',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Text(
                          'Serial Key / License (ถ้ามี)',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _serialKeyCtrl,
                          style: AppTextStyles.bodyMedium,
                          decoration: const InputDecoration(
                            hintText: 'XXXX-XXXX-XXXX-XXXX',
                            prefixIcon: Icon(Icons.key),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],

                      // --- Submit Button ---
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _testAndSave,
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  _isCreatingNew
                                      ? 'สร้างและเริ่มต้นใช้งาน'
                                      : 'เชื่อมต่อฐานข้อมูล',
                                  style: const TextStyle(fontSize: 18),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

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
