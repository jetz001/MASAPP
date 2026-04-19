import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../auth/auth_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../machine_intake/widgets/pin_keypad.dart';
import '../admin/admin_screen.dart'; // Reuse UserRecord model
import '../../../core/theme/ui_scale_provider.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    // We'll initialize with a temporary length and update in build if needed,
    // or just use a fixed length that covers all cases.
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.settings_suggest_outlined,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'การตั้งค่าและความปลอดภัย',
                    style: AppTextStyles.headlineLarge,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'จัดการรหัส PIN สำหรับอนุมัติ และการตั้งค่าระบบความปลอดภัย',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'รหัส PIN อนุมัติ'),
              const Tab(text: 'การแสดงผล'),
              if (user?.isEngineerOrAbove ?? false)
                const Tab(text: 'การปลดล็อก PIN พนักงาน'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              const _MyPinTab(),
              const _DisplaySettingsTab(),
              if (user?.isEngineerOrAbove ?? false) const _UnlockPinTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Tab: My PIN ─────────────────────────────────────────────────────────────

class _MyPinTab extends ConsumerStatefulWidget {
  const _MyPinTab();

  @override
  ConsumerState<_MyPinTab> createState() => _MyPinTabState();
}

class _MyPinTabState extends ConsumerState<_MyPinTab> {
  int _step = 0; // 0: Old PIN, 1: New PIN, 2: Confirm PIN
  String _oldPin = '';
  String _newPin = '';
  String _confirmPin = '';
  String? _error;
  bool _loading = false;

  void _onKeyTap(String key) {
    setState(() {
      _error = null;
      if (_step == 0) {
        if (_oldPin.length < 4) _oldPin += key;
        if (_oldPin.length == 4) _verifyOldPin();
      } else if (_step == 1) {
        if (_newPin.length < 4) _newPin += key;
        if (_newPin.length == 4) setState(() => _step = 2);
      } else if (_step == 2) {
        if (_confirmPin.length < 4) _confirmPin += key;
        if (_confirmPin.length == 4) _saveNewPin();
      }
    });
  }

  void _onBackspace() {
    setState(() {
      if (_step == 0 && _oldPin.isNotEmpty) {
        _oldPin = _oldPin.substring(0, _oldPin.length - 1);
      }
      if (_step == 1 && _newPin.isNotEmpty) {
        _newPin = _newPin.substring(0, _newPin.length - 1);
      }
      if (_step == 2 && _confirmPin.isNotEmpty) {
        _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      }
    });
  }

  Future<void> _verifyOldPin() async {
    final user = ref.read(authProvider);
    if (user == null) return;

    setState(() => _loading = true);
    final repo = ref.read(machineRepositoryProvider);
    final valid = await repo.verifyApprovalPin(user.userId, _oldPin);

    if (valid) {
      setState(() {
        _step = 1;
        _loading = false;
      });
    } else {
      setState(() {
        _oldPin = '';
        _error = 'รหัส PIN เดิมไม่ถูกต้อง';
        _loading = false;
      });
    }
  }

  Future<void> _saveNewPin() async {
    if (_newPin != _confirmPin) {
      setState(() {
        _confirmPin = '';
        _error = 'รหัส PIN ยืนยันไม่ตรงกัน';
      });
      return;
    }

    final user = ref.read(authProvider);
    if (user == null) return;

    setState(() => _loading = true);
    final repo = ref.read(machineRepositoryProvider);
    final err = await repo.changeUserPin(user.userId, _oldPin, _newPin);

    if (err == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('เปลี่ยนรหัส PIN สำเร็จ')));
        setState(() {
          _step = 0;
          _oldPin = '';
          _newPin = '';
          _confirmPin = '';
          _loading = false;
        });
      }
    } else {
      setState(() {
        _error = err;
        _loading = false;
        _confirmPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = 'กรอกรหัส PIN เดิม';
    if (_step == 1) title = 'ตั้งรหัส PIN ใหม่ (4 หลัก)';
    if (_step == 2) title = 'ยืนยันรหัส PIN ใหม่';

    String currentInput = _step == 0
        ? _oldPin
        : (_step == 1 ? _newPin : _confirmPin);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      Text(title, style: AppTextStyles.titleLarge),
                      const SizedBox(height: 24),

                      // Progress Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (i) {
                          final active = i < currentInput.length;
                          return Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? AppColors.primary
                                  : Theme.of(context).dividerColor,
                            ),
                          );
                        }),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ],

                      const SizedBox(height: 32),
                      if (_loading)
                        const CircularProgressIndicator()
                      else
                        PinKeypad(
                          onKeyTap: _onKeyTap,
                          onBackspace: _onBackspace,
                        ),
                    ],
                  ),
                ),
              ),
              if (_step > 0)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _step = 0;
                    _oldPin = '';
                    _newPin = '';
                    _confirmPin = '';
                  }),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('เริ่มใหม่ / ยกเลิก'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tab: Unlock PIN ─────────────────────────────────────────────────────────

class _UnlockPinTab extends ConsumerWidget {
  const _UnlockPinTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(userListProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (users) {
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final u = users[index];
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: u.roleColor.withValues(alpha: 0.1),
                  child: Text(
                    u.fullName.substring(0, 1),
                    style: TextStyle(color: u.roleColor),
                  ),
                ),
                title: Text(u.fullName, style: AppTextStyles.titleSmall),
                subtitle: Text('${u.roleDisplayName} | ${u.deptName ?? "-"}'),
                trailing: ElevatedButton.icon(
                  onPressed: () => _confirmReset(context, ref, u),
                  icon: const Icon(Icons.lock_open_rounded, size: 16),
                  label: const Text('ปลดล็อก PIN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error.withValues(alpha: 0.1),
                    foregroundColor: AppColors.error,
                    elevation: 0,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    WidgetRef ref,
    UserRecord targetUser,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการปลดล็อก PIN'),
        content: Text(
          'คุณต้องการล้างรหัส PIN ของ "${targetUser.fullName}" ใช่หรือไม่?\nพนักงานจะต้องตั้งรหัส PIN ใหม่ในการอนุมัติครั้งถัดไป',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('ยืนยันปลดล็อก'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(machineRepositoryProvider).resetUserPin(targetUser.userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ปลดล็อก PIN ของ ${targetUser.fullName} เรียบร้อยแล้ว',
            ),
          ),
        );
      }
    }
  }
}

// ─── Tab: Display Settings ───────────────────────────────────────────────────

class _DisplaySettingsTab extends ConsumerWidget {
  const _DisplaySettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(uiScaleProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            context,
            title: 'ขนาดส่วนต่อประสานผู้ใช้ (UI Scale)',
            subtitle:
                'ปรับขนาดของตัวอักษรและองค์ประกอบต่างๆ ในแอปให้เล็กลงหรือใหญ่ขึ้น',
            icon: HugeIcons.strokeRoundedAiView,
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('เล็ก (75%)', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: scale,
                        min: 0.75,
                        max: 1.25,
                        divisions: 10,
                        label: '${(scale * 100).toInt()}%',
                        onChanged: (val) {
                          ref.read(uiScaleProvider.notifier).setScale(val);
                        },
                      ),
                    ),
                    const Text('ใหญ่ (125%)', style: TextStyle(fontSize: 14)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ปัจจุบัน: ${(scale * 100).toInt()}%',
                        style: AppTextStyles.labelMedium,
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(uiScaleProvider.notifier).setScale(1.0),
                        child: const Text('รีเซ็ตเป็นค่าเริ่มต้น'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSection(
            context,
            title: 'ขนาดหน้าต่างแอป',
            subtitle:
                'เลือกขนาดหน้าต่างมาตรฐาน VGA/SVGA/XGA/SXGA/UXGA หรือ Wide Screen ตามความละเอียดจอ',
            icon: Icons.aspect_ratio,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _buildWindowSizeButton(
                      context,
                      'VGA 640x480',
                      const Size(640, 480),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'SVGA 800x600',
                      const Size(800, 600),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'XGA 1024x768',
                      const Size(1024, 768),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'SXGA 1280x1024',
                      const Size(1280, 1024),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'SXGA+ 1400x1050',
                      const Size(1400, 1050),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'UXGA 1600x1200',
                      const Size(1600, 1200),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'WVGA 840x480',
                      const Size(840, 480),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'WXGA 1280x800',
                      const Size(1280, 800),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'WXGA+ 1440x900',
                      const Size(1440, 900),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'WSXGA 1680x1050',
                      const Size(1680, 1050),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'WUXGA 1920x1200',
                      const Size(1920, 1200),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'HD Ready 1366x768',
                      const Size(1366, 768),
                    ),
                    _buildWindowSizeButton(
                      context,
                      'Full HD 1920x1080',
                      const Size(1920, 1080),
                    ),
                    _buildCurrentWindowSizeButton(context),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FutureBuilder<Size>(
                  future: _currentWindowSize(),
                  builder: (context, snapshot) {
                    final size = snapshot.data;
                    return Text(
                      size == null
                          ? 'กำลังโหลดขนาดหน้าต่าง...'
                          : 'ขนาดหน้าต่างปัจจุบัน: ${size.width.toInt()}x${size.height.toInt()}',
                      style: AppTextStyles.bodySmall,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primary),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'หากแอปดู "ล้นหน้าจอ" หรือองค์ประกอบต่างๆ ใหญ่เกินไป แนะนำให้ปรับขนาดลงครับ',
                      style: TextStyle(fontSize: 13),
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

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required dynamic icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            icon is IconData
                ? Icon(icon, size: 20, color: AppColors.primary)
                : HugeIcon(icon: icon, size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTextStyles.titleLarge),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTextStyles.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        child,
      ],
    );
  }

  Future<Size> _currentWindowSize() async {
    final bounds = await windowManager.getBounds();
    return bounds.size;
  }

  Widget _buildWindowSizeButton(BuildContext context, String label, Size size) {
    return ElevatedButton(
      onPressed: () async {
        await windowManager.setSize(size);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _buildCurrentWindowSizeButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final currentSize = await _currentWindowSize();
        await windowManager.setSize(currentSize);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.primary,
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: const Text('ขนาดปัจจุบัน'),
    );
  }
}
