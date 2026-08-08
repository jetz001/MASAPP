import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_text_styles.dart';
import 'auth_provider.dart';
import 'db_setup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePass = true;
  bool _loading = false;
  bool _rememberMe = false;
  String? _errorMessage;

  static const _kUser = 'masapp_saved_username';
  static const _kPass = 'masapp_saved_password';
  static const _kRemember = 'masapp_remember_me';

  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
    );
    _fadeCtrl.forward();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_kRemember) ?? false;
    if (remember) {
      if (mounted) {
        setState(() {
          _rememberMe = true;
          _usernameCtrl.text = prefs.getString(_kUser) ?? '';
          _passwordCtrl.text = prefs.getString(_kPass) ?? '';
        });
      }
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_kUser, _usernameCtrl.text.trim());
      await prefs.setString(_kPass, _passwordCtrl.text);
      await prefs.setBool(_kRemember, true);
    } else {
      await prefs.remove(_kUser);
      await prefs.remove(_kPass);
      await prefs.setBool(_kRemember, false);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final error = await ref.read(authProvider.notifier).login(
          _usernameCtrl.text.trim(),
          _passwordCtrl.text,
        );

    if (!mounted) return;

    if (error == null) {
      await _saveCredentials();
      widget.onLoggedIn();
    } else {
      _passwordCtrl.clear();
      _passwordFocus.requestFocus();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _loading = false;
        _errorMessage = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Deep slate/navy background
      body: Row(
        children: [
          // ── LEFT SIDE (Hero Image for Desktop) ───────────────────────
          if (isDesktop)
            Expanded(
              flex: 55,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Hero Background Image
                  Image.asset(
                    'assets/images/login_hero.jpg',
                    fit: BoxFit.cover,
                  ),
                  // Dark Overlay Gradient for blending with right panel
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          const Color(0xFF0B0F19), // Solid dark at the right edge
                          const Color(0xFF0B0F19).withValues(alpha: 0.8),
                          const Color(0xFF0B0F19).withValues(alpha: 0.4), // Darken the left side too
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  // Dark Overlay Gradient from bottom for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF0B0F19).withValues(alpha: 0.95),
                          const Color(0xFF0B0F19).withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.3, 0.6],
                      ),
                    ),
                  ),
                  // Text overlay
                  Positioned(
                    left: 60,
                    bottom: 80,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D4ED8).withValues(alpha: 0.3), // Slightly more opaque
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.6)), // Brighter border
                            ),
                            child: const Text(
                              'ระบบจัดการงานซ่อมบำรุงอัจฉริยะ',
                              style: TextStyle(
                                color: Color(0xFF93C5FD), // Brighter blue
                                fontSize: 16, // Slightly larger
                                letterSpacing: 1,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'แม่นยำ.\nน่าเชื่อถือ.\nทรงประสิทธิภาพ.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: -1,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  offset: Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'ยกระดับมาตรฐานการซ่อมบำรุงโรงงานสู่ยุคดิจิทัล',
                            style: TextStyle(
                              color: Color(0xFFD1D5DB), // Lighter gray for better contrast
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  offset: Offset(0, 2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── RIGHT SIDE (Login Panel) ──────────────────────────────────
          Expanded(
            flex: isDesktop ? 45 : 100,
            child: Container(
              color: const Color(0xFF0B0F19), // Matches gradient edge
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
                        child: _buildLoginForm(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DbSetupScreen(
                onConnected: () {
                  if (mounted) {
                    Navigator.pop(context); // Go back to login
                    setState(() => _errorMessage = null); // clear error message
                  }
                },
              ),
            ),
          );
        },
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: const Color(0xFF9CA3AF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        icon: const Icon(Icons.settings_suggest_rounded, size: 20),
        label: const Text('ตั้งค่าฐานข้อมูล', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo + Title
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.precision_manufacturing_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 32),
              Text(
                'เข้าสู่ระบบ',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ยินดีต้อนรับกลับเข้าสู่ MASAPP',
                style: AppTextStyles.titleMedium.copyWith(
                  color: const Color(0xFF9CA3AF),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Username field
              _buildFieldLabel('รหัสพนักงาน / ชื่อผู้ใช้'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _usernameCtrl,
                focusNode: _usernameFocus,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                decoration: _fieldDecoration(
                  hint: 'กรอกรหัสพนักงานของคุณ',
                  icon: Icons.person_outline_rounded,
                ),
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกรหัสพนักงาน' : null,
              ),

              const SizedBox(height: 24),

              // Password field
              _buildFieldLabel('รหัสผ่าน'),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final offset = (_shakeCtrl.isAnimating)
                      ? 8 * (0.5 - (_shakeAnim.value % 1.0)).abs() * 2
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: TextFormField(
                  controller: _passwordCtrl,
                  focusNode: _passwordFocus,
                  obscureText: _obscurePass,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: _fieldDecoration(
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      padding: const EdgeInsets.all(12),
                      icon: Icon(
                        _obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 22,
                        color: const Color(0xFF64748B),
                      ),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  onFieldSubmitted: (_) => _login(),
                  validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกรหัสผ่าน' : null,
                ),
              ),

              // Error message
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Remember Me
              const SizedBox(height: 24),
              InkWell(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          activeColor: const Color(0xFF3B82F6),
                          checkColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF64748B), width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'จำข้อมูลการเข้าสู่ระบบไว้',
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Login button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1E3A8A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'เข้าสู่ระบบ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 32),

              // Footer note
              const Center(
                child: Text(
                  'พบปัญหาการเข้าสู่ระบบ?\nติดต่อแผนกไอที เบอร์ภายใน 1122',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFFE2E8F0), // Light slate
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 15),
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Icon(icon, size: 24, color: const Color(0xFF64748B)),
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF1E293B), // Dark input background
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      errorStyle: const TextStyle(color: Color(0xFFF87171), fontSize: 13, fontWeight: FontWeight.bold),
    );
  }
}
