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
        vsync: this, duration: const Duration(milliseconds: 600));
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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6), // Light gray background
      body: Stack(
        children: [
          // Subtle background decoration
          Positioned.fill(child: _BackgroundDecorationLight()),

          // ── Login Card ─────────────────────────────────────────────────
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                  child: _buildCard(),
                ),
              ),
            ),
          ),

          // ── Database Setup Button (Bottom Right) ───────────────────────
          Positioned(
            bottom: 24,
            right: 24,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
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
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.settings_suggest_rounded, color: Color(0xFF6B7280), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'ตั้งค่าฐานข้อมูล',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: const Color(0xFF4B5563),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: 500, // Made wider for older users
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 40,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top accent line
          Container(
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF1D4ED8),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(48.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo + Title (Centered)
                  Column(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.asset('assets/images/masapp_logo.png', fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'เข้าสู่ระบบ',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: const Color(0xFF111827),
                          fontWeight: FontWeight.w700,
                          fontSize: 28, // Large text
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MASAPP Maintenance Super App',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: const Color(0xFF6B7280),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Username field
                  _buildFieldLabel('รหัสพนักงาน / ชื่อผู้ใช้'),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _usernameCtrl,
                    focusNode: _usernameFocus,
                    autofocus: true,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18, // Large text
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _fieldDecoration(
                      hint: 'กรอกรหัสพนักงานของคุณ',
                      icon: Icons.person_outline_rounded,
                    ),
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'กรุณากรอกรหัสพนักงาน' : null,
                  ),

                  const SizedBox(height: 28),

                  // Password field
                  _buildFieldLabel('รหัสผ่าน'),
                  const SizedBox(height: 10),
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
                        color: Color(0xFF111827),
                        fontSize: 18,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: _fieldDecoration(
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          padding: const EdgeInsets.all(12),
                          icon: Icon(
                            _obscurePass
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 24,
                            color: const Color(0xFF6B7280),
                          ),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                      onFieldSubmitted: (_) => _login(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'กรุณากรอกรหัสผ่าน' : null,
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
                                color: const Color(0xFFFEF2F2),
                                border: Border.all(
                                    color: const Color(0xFFFECACA), width: 1.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: Color(0xFFEF4444), size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: Color(0xFFB91C1C),
                                        fontSize: 16, // Large text
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

                  // ── Remember Me ────────────────────────────────────────
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Transform.scale(
                            scale: 1.3, // Larger checkbox
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v ?? false),
                              activeColor: const Color(0xFF1D4ED8),
                              checkColor: Colors.white,
                              side: const BorderSide(
                                  color: Color(0xFF9CA3AF), width: 2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Text(
                            'ให้ระบบจำรหัสผู้ใช้งานของฉันไว้',
                            style: TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 16, // Accessible size
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Login button
                  SizedBox(
                    height: 56, // Taller button
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D4ED8),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF93C5FD),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), // Softer corners
                        ),
                        elevation: 2,
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
                                fontSize: 20, // Large button text
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Footer note
                  const Center(
                    child: Text(
                      'หากพบปัญหาการเข้าสู่ระบบ\nกรุณาติดต่อแผนกไอที เบอร์ภายใน 1122',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF374151),
        fontSize: 16, // Large label
        fontWeight: FontWeight.bold,
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
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
      prefixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Icon(icon, size: 28, color: const Color(0xFF6B7280)),
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1D4ED8), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
      ),
      errorStyle: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.bold),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background: Simple clean light decoration
// ─────────────────────────────────────────────────────────────────────────────
class _BackgroundDecorationLight extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LightBgPainter());
  }
}

class _LightBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Large ambient soft blue circle top right
    final topGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFDBEAFE).withValues(alpha: 0.6),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.8, size.height * 0.2),
        radius: size.width * 0.4,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.2), size.width * 0.4, topGlow);

    // Large ambient soft blue circle bottom left
    final bottomGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFEFF6FF).withValues(alpha: 0.8),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.1, size.height * 0.9),
        radius: size.width * 0.5,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.9), size.width * 0.5, bottomGlow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
