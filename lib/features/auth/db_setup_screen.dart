import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import '../../core/config/app_config.dart';
import '../../core/utils/crypto_utils.dart';
import '../../core/database/db_connection.dart';
import '../../core/database/db_initializer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/database/db_status_provider.dart';
import '../../core/widgets/db_connection_error_dialog.dart';

/// First-launch setup wizard — Windows OOBE-inspired two-column layout.
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
  late final AnimationController _bgAnimCtrl;

  @override
  void initState() {
    super.initState();
    _bgAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
    _initDefaultPath();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dbStatus = ref.read(dbStatusProvider);
      if (!dbStatus.isConnected && dbStatus.errorMessage != null) {
        if (dbStatus.dbPath != null) {
          _pathCtrl.text = dbStatus.dbPath!;
          _isCreatingNew = false;
        }
        DbConnectionErrorDialog.show(context);
      }
    });
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
    _bgAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite', 'sqlite3'],
        dialogTitle: 'เลือกไฟล์ฐานข้อมูล MASAPP',
      );
      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        setState(() => _pathCtrl.text = result.files.single.path!);
      }
    } catch (e) {
      Logger().e('Error picking file: $e');
    }
  }

  Future<void> _selectFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'เลือกโฟลเดอร์สำหรับสร้างฐานข้อมูลใหม่',
      );
      if (result != null && result.trim().isNotEmpty) {
        final folder = result.trim().replaceAll('/', '\\');
        setState(() => _pathCtrl.text = p.join(folder, 'masapp.db'));
      }
    } catch (e) {
      Logger().e('Error selecting folder: $e');
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _logoBase64 = base64Encode(bytes));
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
      : const ['รูปแบบการเริ่มต้น', 'ตำแหน่งฐานข้อมูล', 'สรุปก่อนเชื่อมต่อ'];

  void _setMode(bool createNew) {
    setState(() {
      _isCreatingNew = createNew;
      if (_currentStep > _maxStep) _currentStep = _maxStep;
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
      case 3:
        if (!_isCreatingNew) return true;
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
      if (_currentStep < _maxStep) _currentStep++;
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

    // Fresh initialization is intentionally restricted to this computer.
    // A network database is shared data and must only ever be connected to,
    // never created or reinitialized by this setup flow.
    if (_isCreatingNew && DbConnection.isNetworkPath(path)) {
      _setFailure(
        'Cannot create a new database on a network drive. Select a local folder on this computer.',
      );
      return;
    }

    if (!_isCreatingNew) {
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
      await DbConnection.instance.connect(
        config,
        skipInitialization: _isCreatingNew,
      );
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

  // ─── Illustration helpers ────────────────────────────────────────────────

  IconData get _stepIcon {
    switch (_currentStep) {
      case 0:
        return Icons.storage_rounded;
      case 1:
        return Icons.folder_open_rounded;
      case 2:
        return Icons.business_rounded;
      case 3:
        return Icons.shield_rounded;
      case 4:
        return Icons.fact_check_rounded;
      default:
        return Icons.settings_rounded;
    }
  }

  Color get _stepColor {
    switch (_currentStep) {
      case 0:
        return AppColors.primary;
      case 1:
        return const Color(0xFF0EA5E9);
      case 2:
        return const Color(0xFF10B981);
      case 3:
        return const Color(0xFF8B5CF6);
      case 4:
        return const Color(0xFFF59E0B);
      default:
        return AppColors.primary;
    }
  }

  // ─── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBEFF9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF64748B)),
          onPressed: () {
            if (_currentStep > 0 && !_setupCompleted && !_showPreparing) {
              _goBack();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: AnimatedBuilder(
        animation: _bgAnimCtrl,
        builder: (context, child) {
          final t = _bgAnimCtrl.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    const Color(0xFFEDF1FB),
                    const Color(0xFFE8ECFA),
                    t,
                  )!,
                  Color.lerp(
                    const Color(0xFFE2E8F7),
                    const Color(0xFFDAE1F4),
                    t,
                  )!,
                ],
              ),
            ),
            child: child,
          );
        },
        child: Form(
          key: _formKey,
          child: Stack(
            children: [
              // ── Main body ──────────────────────────────────────────
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(64, 0, 64, 52),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _setupCompleted
                        ? _buildCompletionView()
                        : _showPreparing
                        ? _buildPreparingView()
                        : _buildWizardLayout(),
                  ),
                ),
              ),
              // ── Step dots pinned at bottom ──────────────────────────
              if (!_setupCompleted && !_showPreparing)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: _BottomStepDots(
                    currentStep: _currentStep,
                    totalSteps: _stepTitles.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Two-column wizard layout ────────────────────────────────────────────

  Widget _buildWizardLayout() {
    return Row(
      key: ValueKey('wizard-$_currentStep-$_isCreatingNew'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left: animated illustration ──────────────────────────────
        Expanded(
          flex: 4,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.86, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: child,
                ),
              ),
              child: _StepIllustration(
                key: ValueKey('illus-$_currentStep'),
                icon: _stepIcon,
                color: _stepColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 40),
        // ── Right: content column ────────────────────────────────────
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              // Page header (fixed)
              _buildPageHeader(),
              const SizedBox(height: 10),
              if (!ref.watch(dbStatusProvider).isConnected &&
                  ref.watch(dbStatusProvider).errorMessage != null) ...[
                Builder(builder: (context) {
                  final dbStatus = ref.watch(dbStatusProvider);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.red, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '⚠️ ไม่สามารถเชื่อมต่อฐานข้อมูลล่าสุดได้ (${dbStatus.dbPath ?? ""})',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.red.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dbStatus.errorMessage ??
                                    "ไม่สามารถเปิดไฟล์ฐานข้อมูลได้",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                          ),
                          icon: dbStatus.isRetrying
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text('ลองใหม่',
                              style: TextStyle(fontSize: 11)),
                          onPressed: dbStatus.isRetrying
                              ? null
                              : () async {
                                  final ok = await ref
                                      .read(dbStatusProvider.notifier)
                                      .retryConnect();
                                  if (ok) widget.onConnected();
                                },
                        ),
                      ],
                    ),
                  );
                }),
              ],
              // Hint box
              _SetupHintBox(
                icon: Icons.lightbulb_outline_rounded,
                title: _isCreatingNew
                    ? 'แนะนำสำหรับการติดตั้งครั้งแรก'
                    : 'สำหรับเครื่องที่ต้องการใช้ฐานข้อมูลร่วม',
                message: _isCreatingNew
                    ? 'ระบบจะสร้างฐานข้อมูลใหม่แบบ local-first พร้อมตั้งค่า Admin คนแรกให้ทันทีหลังจบขั้นตอนนี้'
                    : 'ใช้โหมดนี้เมื่อมีไฟล์ฐานข้อมูล MASAPP อยู่แล้ว เช่น ฐานกลางบน server',
              ),
              const SizedBox(height: 16),
              // Let long summary/setup steps scroll instead of overflowing the
              // window; keep navigation visible at the bottom.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: _buildWizardStep(),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 16),
                        _StatusBanner(ok: _statusOk, message: _statusMessage!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Navigation
              _buildNavRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.storage_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ตั้งค่าระบบครั้งแรก',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'แนะนำให้สร้างฐานข้อมูลใหม่ในเครื่องนี้ก่อน'
                ' แล้วค่อยเชื่อมฐานข้อมูลส่วนกลางภายหลัง',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_currentStep > 0) ...[
          TextButton(
            onPressed: _loading ? null : _goBack,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('← ย้อนกลับ', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
        ],
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _loading
                ? null
                : (_currentStep == _maxStep ? _testAndSave : _goNext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _currentStep == _maxStep
                        ? (_isCreatingNew ? 'เริ่มใช้งาน  →' : 'เชื่อมต่อ  →')
                        : 'ถัดไป  →',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ─── Step content ────────────────────────────────────────────────────────

  Widget _buildFieldLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildWizardStep() {
    switch (_currentStep) {
      case 0:
        return Column(
          key: const ValueKey('step-0'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'เลือกรูปแบบการเริ่มต้น',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'คุณสามารถเริ่มจากฐานข้อมูลในเครื่องก่อน แล้วค่อยสลับไปฐานกลางในภายหลังได้',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            _OobeListItem(
              icon: Icons.add_box_rounded,
              title: 'สร้างฐานข้อมูลใหม่',
              subtitle: 'แนะนำสำหรับลงครั้งแรก',
              selected: _isCreatingNew,
              onTap: () => _setMode(true),
            ),
            const SizedBox(height: 8),
            _OobeListItem(
              icon: Icons.link_rounded,
              title: 'เชื่อมต่อฐานข้อมูลเดิม',
              subtitle: 'สำหรับเครื่องลูกข่าย',
              selected: !_isCreatingNew,
              onTap: () => _setMode(false),
            ),
          ],
        );

      case 1:
        return Column(
          key: const ValueKey('step-1'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ตำแหน่งฐานข้อมูล',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            _buildFieldLabel('ที่อยู่ไฟล์ฐานข้อมูล (.db)'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _pathCtrl,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color(0xFF1E293B),
                    ),
                    decoration: InputDecoration(
                      hintText: _isCreatingNew
                          ? r'C:\Users\...\MASAPP\data\masapp.db'
                          : '\\\\SERVER\\Shared\\masapp.db',
                      prefixIcon: const Icon(Icons.description_outlined),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (v) {
                      if (_currentStep != 1) return null;
                      return v == null || v.isEmpty
                          ? 'กรุณาเลือกหรือระบุที่อยู่ไฟล์'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isCreatingNew ? _selectFolder : _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: Text(_isCreatingNew ? 'เลือกโฟลเดอร์' : 'เลือกไฟล์'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
        );

      case 2:
        if (!_isCreatingNew) return _buildSummaryStep();
        return Column(
          key: const ValueKey('step-2'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ข้อมูลองค์กร',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo picker
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('โลโก้บริษัท'),
                    GestureDetector(
                      onTap: _pickLogo,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
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
                                    Icons.add_a_photo_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 24,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'เลือก',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                // Company + serial
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('ชื่อบริษัท / องค์กร'),
                      TextFormField(
                        controller: _companyCtrl,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: const Color(0xFF1E293B),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'โรงงานตัวอย่าง จำกัด',
                          prefixIcon: Icon(Icons.business),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFieldLabel('Serial Key / License (ถ้ามี)'),
                      TextFormField(
                        controller: _serialKeyCtrl,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: const Color(0xFF1E293B),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          prefixIcon: Icon(Icons.key),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );

      case 3:
        return Column(
          key: const ValueKey('step-3'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ตั้งค่า Admin คนแรก',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 10),
            _buildFieldLabel('ชื่อผู้ใช้งาน Admin คนแรก'),
            TextFormField(
              controller: _adminUsernameCtrl,
              style: AppTextStyles.bodyMedium.copyWith(
                color: const Color(0xFF1E293B),
              ),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) {
                if (!_isCreatingNew || _currentStep != 3) return null;
                return v == null || v.isEmpty ? 'กรุณาระบุ Username' : null;
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('รหัสผ่าน Admin'),
                      TextFormField(
                        controller: _adminPassCtrl,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: const Color(0xFF1E293B),
                        ),
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'อย่างน้อย 6 ตัว',
                          prefixIcon: Icon(Icons.lock),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (v) {
                          if (!_isCreatingNew || _currentStep != 3) {
                            return null;
                          }
                          if (v == null || v.isEmpty) {
                            return 'กรุณาระบุรหัสผ่าน';
                          }
                          if (v.length < 6) return 'อย่างน้อย 6 ตัวอักษร';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('ยืนยันรหัสผ่าน'),
                      TextFormField(
                        controller: _confirmAdminPassCtrl,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: const Color(0xFF1E293B),
                        ),
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'กรอกซ้ำอีกครั้ง',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                          filled: true,
                          fillColor: Colors.white,
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
            const SizedBox(height: 10),
            _buildFieldLabel('Approval PIN สำหรับอนุมัติ'),
            TextFormField(
              controller: _approvalPinCtrl,
              style: AppTextStyles.bodyMedium.copyWith(
                color: const Color(0xFF1E293B),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'ตัวเลขอย่างน้อย 4 หลัก',
                prefixIcon: Icon(Icons.pin_outlined),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (v) {
                if (!_isCreatingNew || _currentStep != 3) return null;
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'กรุณาระบุ PIN';
                if (!RegExp(r'^\d{4,}$').hasMatch(value)) {
                  return 'PIN ต้องเป็นตัวเลขอย่างน้อย 4 หลัก';
                }
                return null;
              },
            ),
          ],
        );

      case 4:
        return _buildSummaryStep();

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSummaryStep() {
    return Column(
      key: const ValueKey('step-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'สรุปก่อนดำเนินการ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 10),
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
          const _SummaryRow(
            label: 'AI & Knowledge Store',
            value: 'Parallel Vector DB & Local Embedding พร้อมใช้งาน',
          ),
        ],
        const SizedBox(height: 10),
        _SetupHintBox(
          icon: Icons.verified_user_outlined,
          title: _isCreatingNew ? 'พร้อมสร้างระบบ' : 'พร้อมเชื่อมต่อ',
          message: _isCreatingNew
              ? 'เมื่อกดเริ่มใช้งาน ระบบจะสร้าง schema, seed ข้อมูลพื้นฐาน และตั้ง Admin คนแรกตามข้อมูลที่กรอกไว้'
              : 'เมื่อกดเชื่อมต่อ ระบบจะบันทึก config ของเครื่องนี้โดยไม่แก้ไขข้อมูลในฐานเดิม',
        ),
      ],
    );
  }

  // ─── Completion view ─────────────────────────────────────────────────────

  Widget _buildCompletionView() {
    return Center(
      key: const ValueKey('completion'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _completionTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _completionMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'สิ่งที่พร้อมใช้งานแล้ว',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
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
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: widget.onConnected,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'เริ่มใช้งาน MASAPP  →',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Preparing view ──────────────────────────────────────────────────────

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

    return Center(
      key: const ValueKey('preparing'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isCreatingNew
                  ? 'กำลังเตรียมระบบ...'
                  : 'กำลังเตรียมการเชื่อมต่อ...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isCreatingNew
                  ? 'ระบบกำลังบันทึกการตั้งค่า สร้างสภาพแวดล้อมเริ่มต้น และตรวจสอบความพร้อม'
                  : 'ระบบกำลังบันทึกการตั้งค่าและตรวจสอบการเชื่อมต่อฐานข้อมูล',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'ความคืบหน้า',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_preparingProgress * 100).round()}%',
                        style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: _preparingProgress,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Align(
                      key: ValueKey('stage-$_preparingStage'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        stageTexts[_preparingStage],
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < stageTexts.length; i++)
                    _PreparingStepBullet(
                      text: stageTexts[i],
                      active: i == _preparingStage,
                      done:
                          i < _preparingStage ||
                          (_preparingProgress >= 1.0 && i == _preparingStage),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget components
// ─────────────────────────────────────────────────────────────────────────────

/// Concentric-circle illustration used in the left panel.
class _StepIllustration extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _StepIllustration({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer soft ring
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.06),
            ),
          ),
          // Mid ring
          Container(
            width: 165,
            height: 165,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
          ),
          // Core circle with gradient
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.82), color],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 52),
          ),
        ],
      ),
    );
  }
}

/// OOBE-style selectable list item.
class _OobeListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _OobeListItem({
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFDDE1ED),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : const Color(0xFF64748B),
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.78)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomStepDots extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _BottomStepDots({required this.currentStep, required this.totalSteps});

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
          width: isActive ? 22 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : isDone
                ? AppColors.primary.withValues(alpha: 0.35)
                : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A2E),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    height: 1.4,
                    fontSize: 12,
                    color: Color(0xFF4338CA),
                  ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error,
            color: ok ? AppColors.success : AppColors.error,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: ok ? AppColors.success : AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 11, color: AppColors.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
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
        : (active ? AppColors.primary : const Color(0xFFCBD5E1));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: active || done ? 0.14 : 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check : (active ? Icons.sync_rounded : Icons.circle),
              size: done || active ? 11 : 6,
              color: accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: active || done
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFF94A3B8),
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
