import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

class _DbSetupScreenState extends ConsumerState<DbSetupScreen>
    with SingleTickerProviderStateMixin {
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
  int _currentStep = 0;
  bool _showPreparing = false;
  bool _setupCompleted = false;
  String _completionTitle = 'Setup completed';
  String _completionMessage = '';
  double _preparingProgress = 0.0;
  int _preparingStage = 0;

  String? _statusMessage;
  bool _statusOk = false;
  late final AnimationController _bgAnimationCtrl;

  @override
  void initState() {
    super.initState();
    _bgAnimationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
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
    _bgAnimationCtrl.dispose();
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

  int get _maxStep => _isCreatingNew ? 4 : 2;

  List<String> get _stepTitles => _isCreatingNew
      ? const [
          'รูปแบบการเริ่มต้น',
          'ตำแหน่งฐานข้อมูล',
          'ข้อมูลองค์กร',
          'ตั้งค่า Admin',
          'สรุปก่อนเริ่มใช้งาน',
        ]
      : const [
          'รูปแบบการเริ่มต้น',
          'ตำแหน่งฐานข้อมูล',
          'สรุปก่อนเชื่อมต่อ',
        ];

  void _setMode(bool createNew) {
    setState(() {
      _isCreatingNew = createNew;
      if (_currentStep > _maxStep) {
        _currentStep = _maxStep;
      }
      _statusMessage = null;
    });
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return true;
      case 1:
        if (_pathCtrl.text.trim().isEmpty) {
          _setFailure('กรุณาเลือกหรือระบุที่อยู่ไฟล์ฐานข้อมูล');
          return false;
        }
        return true;
      case 2:
        if (_isCreatingNew) {
          return true;
        }
        return true;
      case 3:
        if (!_isCreatingNew) {
          return true;
        }
        return _formKey.currentState?.validate() ?? false;
      case 4:
        return true;
      default:
        return true;
    }
  }

  void _goNext() {
    if (!_validateCurrentStep()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _statusMessage = null;
      if (_currentStep < _maxStep) {
        _currentStep++;
      }
    });
  }

  void _goBack() {
    if (_currentStep == 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _statusMessage = null;
      _currentStep--;
    });
  }

  Future<void> _runPreparingSequence() async {
    const progressStops = [0.12, 0.38, 0.68, 0.9, 1.0];
    for (var i = 0; i < progressStops.length; i++) {
      if (!mounted) return;
      setState(() {
        _preparingStage = i.clamp(0, 2);
        _preparingProgress = progressStops[i];
      });
      await Future.delayed(
        Duration(milliseconds: i == progressStops.length - 1 ? 260 : 320),
      );
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
        _statusMessage = null;
        _loading = false;
        _showPreparing = true;
        _preparingProgress = 0.12;
        _preparingStage = 0;
      });
      await _runPreparingSequence();
      if (!mounted) return;
      setState(() {
        _showPreparing = false;
        _setupCompleted = true;
        _completionTitle = _isCreatingNew
            ? 'Setup completed'
            : 'เชื่อมต่อฐานข้อมูลสำเร็จ';
        _completionMessage = _isCreatingNew
            ? 'ระบบได้สร้างฐานข้อมูลใหม่ ตั้งค่าองค์กร และเตรียมบัญชี Admin คนแรกเรียบร้อยแล้ว คุณสามารถเริ่มใช้งาน MASAPP ได้ทันที'
            : 'ระบบได้บันทึกการตั้งค่าของเครื่องนี้และเชื่อมต่อฐานข้อมูลเรียบร้อยแล้ว พร้อมเข้าสู่ระบบเพื่อใช้งานต่อ';
      });
    } catch (e) {
      Logger().e('[Setup] Error while saving config or connecting DB: $e');
      _setFailure('บันทึกการตั้งค่าหรือเชื่อมต่อฐานข้อมูลไม่สำเร็จ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B1A),
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
      body: AnimatedBuilder(
        animation: _bgAnimationCtrl,
        builder: (context, _) {
          final progress = _bgAnimationCtrl.value;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF071226),
                        Color.lerp(
                          const Color(0xFF11193A),
                          const Color(0xFF1A1440),
                          progress,
                        )!,
                        const Color(0xFF090D1B),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -80 + (progress * 70),
                top: 60,
                child: _AnimatedGlowOrb(
                  size: 240,
                  colors: const [Color(0xFF5F5BFF), Color(0x003E37FF)],
                ),
              ),
              Positioned(
                right: -60,
                top: 180 - (progress * 40),
                child: _AnimatedGlowOrb(
                  size: 200,
                  colors: const [Color(0xFF27D2BF), Color(0x0027D2BF)],
                ),
              ),
              Positioned(
                right: 80 - (progress * 50),
                bottom: -40,
                child: _AnimatedGlowOrb(
                  size: 260,
                  colors: const [Color(0xFF6F6FFF), Color(0x001A1440)],
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 720,
                    child: Card(
                      color: const Color(0xCC131426),
                      elevation: 16,
                      shadowColor: Colors.black.withValues(alpha: 0.22),
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Form(
                          key: _formKey,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.04, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: _setupCompleted
                                ? _buildCompletionView()
                                : _showPreparing
                                ? _buildPreparingView()
                                : Column(
                                    key: ValueKey(
                                      'wizard-$_currentStep-${_isCreatingNew.toString()}',
                                    ),
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(
                                                alpha: 0.16,
                                              ),
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
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
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(0.03, 0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Container(
                                          key: ValueKey(
                                            'step-body-$_currentStep-${_isCreatingNew.toString()}',
                                          ),
                                          child: _buildWizardStep(),
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      Row(
                                        children: [
                                          if (_currentStep > 0)
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: _loading
                                                    ? null
                                                    : _goBack,
                                                icon: const Icon(
                                                  Icons.arrow_back_rounded,
                                                ),
                                                label: const Text('ย้อนกลับ'),
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize:
                                                      const Size.fromHeight(56),
                                                ),
                                              ),
                                            ),
                                          if (_currentStep > 0)
                                            const SizedBox(width: 12),
                                          Expanded(
                                            flex: 2,
                                            child: SizedBox(
                                              height: 56,
                                              child: ElevatedButton.icon(
                                                onPressed: _loading
                                                    ? null
                                                    : (_currentStep == _maxStep
                                                          ? _testAndSave
                                                          : _goNext),
                                                icon: _loading
                                                    ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2.2,
                                                        ),
                                                      )
                                                    : Icon(
                                                        _currentStep == _maxStep
                                                            ? (_isCreatingNew
                                                                  ? Icons
                                                                        .rocket_launch_rounded
                                                                  : Icons
                                                                        .link_rounded)
                                                            : Icons
                                                                  .arrow_forward_rounded,
                                                      ),
                                                label: Text(
                                                  _currentStep == _maxStep
                                                      ? (_isCreatingNew
                                                            ? 'เริ่มใช้งาน'
                                                            : 'เชื่อมต่อฐานข้อมูล')
                                                      : 'ถัดไป',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _BottomStepDots(
                                        currentStep: _currentStep,
                                        totalSteps: _stepTitles.length,
                                      ),
                                      if (_statusMessage != null) ...[
                                        const SizedBox(height: 20),
                                        _StatusBanner(
                                          ok: _statusOk,
                                          message: _statusMessage!,
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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

  Widget _buildWizardStep() {
    switch (_currentStep) {
      case 0:
        return _SectionCard(
          title: 'เลือกรูปแบบการเริ่มต้น',
          subtitle:
              'คุณสามารถเริ่มจากฐานข้อมูลในเครื่องก่อน แล้วค่อยสลับไปฐานกลางในภายหลังได้',
          child: Row(
            children: [
              Expanded(
                child: _ModeOptionCard(
                  icon: Icons.add_box_rounded,
                  title: 'สร้างฐานข้อมูลใหม่',
                  subtitle: 'แนะนำสำหรับลงครั้งแรก',
                  selected: _isCreatingNew,
                  onTap: () => _setMode(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeOptionCard(
                  icon: Icons.link_rounded,
                  title: 'เชื่อมต่อฐานข้อมูลเดิม',
                  subtitle: 'สำหรับเครื่องลูกข่าย',
                  selected: !_isCreatingNew,
                  onTap: () => _setMode(false),
                ),
              ),
            ],
          ),
        );
      case 1:
        return _SectionCard(
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
                        prefixIcon: const Icon(Icons.description_outlined),
                      ),
                      validator: (v) {
                        if (_currentStep != 1) return null;
                        return v == null || v.isEmpty
                            ? 'กรุณาเลือกหรือระบุที่อยู่ไฟล์'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isCreatingNew ? _selectFolder : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_isCreatingNew ? 'เลือกโฟลเดอร์' : 'เลือกไฟล์'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SetupHintBox(
                icon: _isCreatingNew
                    ? Icons.save_as_rounded
                    : Icons.info_outline_rounded,
                title: _isCreatingNew
                    ? 'ฐานข้อมูลใหม่จะถูกสร้างตาม path นี้'
                    : 'ระบบจะไม่แก้ไข path เดิมจนกว่าคุณจะกดเชื่อมต่อ',
                message: _isCreatingNew
                    ? 'ถ้าไฟล์นี้มีอยู่แล้ว ระบบจะถามยืนยันก่อนล้างข้อมูลเดิมทุกครั้ง'
                    : 'ใช้ path ของไฟล์ฐานข้อมูล MASAPP ที่มีอยู่แล้วบนเครื่องนี้หรือบน network share',
              ),
            ],
          ),
        );
      case 2:
        if (!_isCreatingNew) {
          return _buildSummaryStep();
        }
        return _SectionCard(
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
        );
      case 3:
        return _SectionCard(
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
                validator: (v) {
                  if (!_isCreatingNew || _currentStep != 3) return null;
                  return v == null || v.isEmpty
                      ? 'กรุณาระบุ Username'
                      : null;
                },
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
                            if (!_isCreatingNew || _currentStep != 3) {
                              return null;
                            }
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
                            prefixIcon: Icon(Icons.verified_user_outlined),
                          ),
                          validator: (v) {
                            if (!_isCreatingNew || _currentStep != 3) {
                              return null;
                            }
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
                  if (!_isCreatingNew || _currentStep != 3) return null;
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
        );
      case 4:
        return _buildSummaryStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSummaryStep() {
    return _SectionCard(
      title: 'สรุปก่อนดำเนินการ',
      subtitle: _isCreatingNew
          ? 'ตรวจสอบข้อมูลทั้งหมดก่อนสร้างฐานข้อมูลและเริ่มใช้งาน'
          : 'ตรวจสอบข้อมูลก่อนบันทึก config และเชื่อมต่อฐานข้อมูล',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            label: 'รูปแบบ',
            value: _isCreatingNew
                ? 'สร้างฐานข้อมูลใหม่ในเครื่องนี้'
                : 'เชื่อมต่อฐานข้อมูลเดิม',
          ),
          _SummaryRow(label: 'ไฟล์ฐานข้อมูล', value: _pathCtrl.text.trim()),
          if (_isCreatingNew) ...[
            _SummaryRow(
              label: 'ชื่อองค์กร',
              value: _companyCtrl.text.trim().isEmpty
                  ? 'ยังไม่ได้ระบุ'
                  : _companyCtrl.text.trim(),
            ),
            _SummaryRow(
              label: 'Serial Key',
              value: _serialKeyCtrl.text.trim().isEmpty
                  ? 'ยังไม่ได้ระบุ'
                  : _serialKeyCtrl.text.trim(),
            ),
            _SummaryRow(
              label: 'Admin คนแรก',
              value: _adminUsernameCtrl.text.trim().isEmpty
                  ? 'ยังไม่ได้ระบุ'
                  : _adminUsernameCtrl.text.trim(),
            ),
            _SummaryRow(
              label: 'โลโก้บริษัท',
              value: _logoBase64 == null ? 'ไม่ได้แนบ' : 'แนบแล้ว',
            ),
          ],
          const SizedBox(height: 16),
          _SetupHintBox(
            icon: Icons.verified_user_outlined,
            title: _isCreatingNew ? 'พร้อมสร้างระบบ' : 'พร้อมเชื่อมต่อ',
            message: _isCreatingNew
                ? 'เมื่อกดเริ่มใช้งาน ระบบจะสร้าง schema, seed ข้อมูลพื้นฐาน และตั้ง Admin คนแรกตามข้อมูลที่กรอกไว้'
                : 'เมื่อกดเชื่อมต่อ ระบบจะบันทึก config ของเครื่องนี้โดยไม่แก้ไขข้อมูลในฐานเดิม',
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionView() {
    return Column(
      key: const ValueKey('setup-completed-view'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.success,
            size: 46,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _completionTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _completionMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        Container(
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
              const Text(
                'สิ่งที่พร้อมใช้งานแล้ว',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _CompletionBullet(
                text: _isCreatingNew
                    ? 'ฐานข้อมูลเริ่มต้นถูกสร้างเรียบร้อย'
                    : 'เครื่องนี้จดจำฐานข้อมูลที่เชื่อมต่อไว้แล้ว',
              ),
              _CompletionBullet(
                text: _isCreatingNew
                    ? 'บัญชี Admin คนแรกพร้อมเข้าสู่ระบบ'
                    : 'พร้อมเข้าสู่ระบบด้วยบัญชีที่มีอยู่ในฐานข้อมูล',
              ),
              _CompletionBullet(
                text: 'สามารถกลับมาแก้ไขการตั้งค่าฐานข้อมูลได้ในภายหลัง',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: widget.onConnected,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text(
              'เริ่มใช้งาน MASAPP',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreparingView() {
    final stageTexts = _isCreatingNew
        ? const [
            'กำลังบันทึก configuration ของเครื่องนี้',
            'กำลังตรวจสอบฐานข้อมูลและสิทธิ์การเข้าถึง',
            'กำลังเตรียมหน้าจอสำหรับเริ่มใช้งาน MASAPP',
          ]
        : const [
            'กำลังตรวจสอบ configuration ที่เลือกไว้',
            'กำลังทดสอบการเชื่อมต่อกับฐานข้อมูล',
            'กำลังเตรียมหน้าจอสำหรับเริ่มใช้งาน MASAPP',
          ];
    return Column(
      key: const ValueKey('setup-preparing-view'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.24),
                  const Color(0xFF27D2BF).withValues(alpha: 0.14),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(22),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          _isCreatingNew ? 'กำลังเตรียมระบบ...' : 'กำลังเตรียมการเชื่อมต่อ...',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _isCreatingNew
              ? 'ระบบกำลังบันทึกการตั้งค่า สร้างสภาพแวดล้อมเริ่มต้น และตรวจสอบความพร้อมก่อนเริ่มใช้งาน'
              : 'ระบบกำลังบันทึกการตั้งค่าของเครื่องนี้และตรวจสอบการเชื่อมต่อฐานข้อมูลให้พร้อมใช้งาน',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.65,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'ความคืบหน้า',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(_preparingProgress * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: _preparingProgress,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Align(
                  key: ValueKey('preparing-stage-$_preparingStage'),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    stageTexts[_preparingStage],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
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
              for (var i = 0; i < stageTexts.length; i++)
                _PreparingStepBullet(
                  text: stageTexts[i],
                  active: i == _preparingStage,
                  done: i < _preparingStage ||
                      (_preparingProgress >= 1.0 && i == _preparingStage),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomStepDots extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _BottomStepDots({
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final isActive = index == currentStep;
        final isDone = index < currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: isActive ? 28 : 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive || isDone
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _AnimatedGlowOrb extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _AnimatedGlowOrb({
    required this.size,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: math.pi / 8,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: colors),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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

class _CompletionBullet extends StatelessWidget {
  final String text;

  const _CompletionBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 14,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparingStepBullet extends StatelessWidget {
  final String text;
  final bool active;
  final bool done;

  const _PreparingStepBullet({
    required this.text,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = done
        ? AppColors.success
        : (active ? AppColors.primary : Colors.white30);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: active || done ? 0.16 : 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check : (active ? Icons.sync_rounded : Icons.circle),
              size: done || active ? 14 : 8,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: active || done ? Colors.white : Colors.white70,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
