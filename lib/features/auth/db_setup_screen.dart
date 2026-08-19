import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/crypto_utils.dart';
import '../../core/database/db_connection.dart';
import '../../core/database/db_initializer.dart';
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
  final _confirmAdminPassCtrl = TextEditingController();
  final _approvalPinCtrl = TextEditingController(text: '123456');
  final _serialKeyCtrl = TextEditingController();
  String? _logoBase64;

  bool _loading = false;
  bool _isCreatingNew = true;

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
    _confirmAdminPassCtrl.dispose();
    _approvalPinCtrl.dispose();
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

        await DbConnection.instance.connect(config, skipInitialization: true);
        await DbInitializer.setupFreshDatabase(
          DbConnection.instance.db,
          adminUsername: _adminUsernameCtrl.text.trim(),
          adminPasswordHash: CryptoUtils.hashPassword(_adminPassCtrl.text),
          approvalPinHash: CryptoUtils.hashPassword(_approvalPinCtrl.text),
          companyName: _companyCtrl.text.trim(),
          serialKey: _serialKeyCtrl.text.trim(),
          orgLogoBase64: _logoBase64,
        );
        Logger().i('[Setup] Fresh database initialized successfully.');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('สร้างฐานข้อมูลใหม่และตั้งค่า Admin สำเร็จ'),
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
            width: 720,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.storage_rounded,
                              color: AppColors.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ตั้งค่าระบบครั้งแรก',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'แนะนำให้สร้างฐานข้อมูลใหม่ในเครื่องนี้ก่อน แล้วค่อยเชื่อมฐานข้อมูลส่วนกลางภายหลังหากต้องการใช้งานหลายเครื่อง',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SetupHintBox(
                        icon: Icons.lightbulb_outline_rounded,
                        title: _isCreatingNew
                            ? 'แนะนำสำหรับการติดตั้งครั้งแรก'
                            : 'สำหรับเครื่องที่ต้องการใช้ฐานข้อมูลร่วม',
                        message: _isCreatingNew
                            ? 'ระบบจะสร้างฐานข้อมูลใหม่แบบ local-first พร้อมตั้งค่า Admin คนแรกให้ทันทีหลังจบขั้นตอนนี้'
                            : 'ใช้โหมดนี้เมื่อมีไฟล์ฐานข้อมูล MASAPP อยู่แล้ว เช่น ฐานกลางบน server หรือฐานที่ย้ายมาจากอีกเครื่อง',
                      ),
                      const SizedBox(height: 24),
                      _SectionCard(
                        title: 'เลือกรูปแบบการเริ่มต้น',
                        subtitle: 'คุณสามารถเริ่มจากฐานข้อมูลในเครื่องก่อน แล้วค่อยสลับไปฐานกลางในภายหลังได้',
                        child: Row(
                          children: [
                            Expanded(
                              child: _ModeOptionCard(
                                icon: Icons.add_box_rounded,
                                title: 'สร้างฐานข้อมูลใหม่',
                                subtitle: 'แนะนำสำหรับลงครั้งแรก',
                                selected: _isCreatingNew,
                                onTap: () => setState(() => _isCreatingNew = true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ModeOptionCard(
                                icon: Icons.link_rounded,
                                title: 'เชื่อมต่อฐานข้อมูลเดิม',
                                subtitle: 'สำหรับเครื่องลูกข่าย',
                                selected: !_isCreatingNew,
                                onTap: () => setState(() => _isCreatingNew = false),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'ตำแหน่งฐานข้อมูล',
                        subtitle: _isCreatingNew
                            ? 'ค่าเริ่มต้นจะอยู่ในเครื่องผู้ใช้เพื่อให้เริ่มใช้งานได้ง่ายที่สุด'
                            : 'ระบุ path ของฐานข้อมูลที่มีอยู่แล้ว',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFieldLabel('ที่อยู่ไฟล์ฐานข้อมูล (.db)'),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _pathCtrl,
                                    style: AppTextStyles.bodyMedium,
                                    decoration: InputDecoration(
                                      hintText: _isCreatingNew
                                          ? r'C:\Users\...\MASAPP\data\masapp.db'
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
                          ],
                        ),
                      ),
                      if (_isCreatingNew) ...[
                        const SizedBox(height: 20),
                        _SectionCard(
                          title: 'ข้อมูลองค์กร',
                          subtitle: 'ใช้สำหรับตั้งค่าระบบเริ่มต้น เอกสาร และ PDF ภายในระบบ',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel('โลโก้บริษัท'),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _pickLogo,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: _logoBase64 != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(16),
                                          child: Image.memory(
                                            base64Decode(_logoBase64!),
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : const Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_a_photo_rounded,
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
                              _buildFieldLabel('ชื่อบริษัท / องค์กร'),
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
                              _buildFieldLabel('Serial Key / License (ถ้ามี)'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _serialKeyCtrl,
                                style: AppTextStyles.bodyMedium,
                                decoration: const InputDecoration(
                                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                                  prefixIcon: Icon(Icons.key),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _SectionCard(
                          title: 'ตั้งค่า Admin คนแรก',
                          subtitle: 'หลังจบขั้นตอนนี้ คุณจะใช้บัญชีนี้เข้าสู่ระบบได้ทันที',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldLabel('ชื่อผู้ใช้งาน Admin คนแรก'),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel('รหัสผ่าน Admin'),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _adminPassCtrl,
                                          style: AppTextStyles.bodyMedium,
                                          obscureText: true,
                                          decoration: const InputDecoration(
                                            hintText: 'อย่างน้อย 6 ตัวอักษร',
                                            prefixIcon: Icon(Icons.lock),
                                          ),
                                          validator: (v) {
                                            if (!_isCreatingNew) return null;
                                            if (v == null || v.isEmpty) {
                                              return 'กรุณาระบุรหัสผ่าน Admin';
                                            }
                                            if (v.length < 6) {
                                              return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                                            }
                                            return null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel('ยืนยันรหัสผ่าน'),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _confirmAdminPassCtrl,
                                          style: AppTextStyles.bodyMedium,
                                          obscureText: true,
                                          decoration: const InputDecoration(
                                            hintText: 'กรอกรหัสผ่านเดิมอีกครั้ง',
                                            prefixIcon: Icon(
                                              Icons.verified_user_outlined,
                                            ),
                                          ),
                                          validator: (v) {
                                            if (!_isCreatingNew) return null;
                                            if (v == null || v.isEmpty) {
                                              return 'กรุณายืนยันรหัสผ่าน';
                                            }
                                            if (v != _adminPassCtrl.text) {
                                              return 'รหัสผ่านไม่ตรงกัน';
                                            }
                                            return null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _buildFieldLabel('Approval PIN สำหรับอนุมัติ'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _approvalPinCtrl,
                                style: AppTextStyles.bodyMedium,
                                keyboardType: TextInputType.number,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: 'ตัวเลขอย่างน้อย 4 หลัก',
                                  prefixIcon: Icon(Icons.pin_outlined),
                                ),
                                validator: (v) {
                                  if (!_isCreatingNew) return null;
                                  final value = v?.trim() ?? '';
                                  if (value.isEmpty) {
                                    return 'กรุณาระบุ PIN สำหรับอนุมัติ';
                                  }
                                  if (!RegExp(r'^\d{4,}$').hasMatch(value)) {
                                    return 'PIN ต้องเป็นตัวเลขอย่างน้อย 4 หลัก';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 20),
                        const _SetupHintBox(
                          icon: Icons.info_outline_rounded,
                          title: 'เชื่อมฐานข้อมูลเดิม',
                          message: 'ใช้ path ของไฟล์ฐานข้อมูล MASAPP ที่มีอยู่แล้วบนเครื่องนี้หรือบน network share จากนั้นระบบจะบันทึก config ให้เครื่องนี้ใช้งานต่อได้ทันที',
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _testAndSave,
                          icon: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : Icon(
                                  _isCreatingNew
                                      ? Icons.rocket_launch_rounded
                                      : Icons.link_rounded,
                                ),
                          label: Text(
                            _isCreatingNew
                                ? 'สร้างระบบและเริ่มใช้งาน'
                                : 'เชื่อมต่อฐานข้อมูล',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_statusMessage != null)
                        _StatusBanner(
                          ok: _statusOk,
                          message: _statusMessage!,
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

  Widget _buildFieldLabel(String title) {
    return Text(
      title,
      style: AppTextStyles.labelLarge.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ModeOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white10,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.white24,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : Colors.white54,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white70 : Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupHintBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _SetupHintBox({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool ok;
  final String message;

  const _StatusBanner({required this.ok, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? AppColors.successContainer : AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? AppColors.success : AppColors.error,
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error,
            color: ok ? AppColors.success : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ok ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
