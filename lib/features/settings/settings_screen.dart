import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../auth/auth_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../machine_intake/widgets/pin_keypad.dart';
import '../admin/admin_screen.dart'; // Reuse UserRecord model

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_suggest_outlined, color: AppColors.primary, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Text('การตั้งค่าและความปลอดภัย', style: AppTextStyles.headlineLarge),
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
              if (user?.isEngineerOrAbove ?? false) const Tab(text: 'การปลดล็อก PIN พนักงาน'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              const _MyPinTab(),
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
      if (_step == 0 && _oldPin.isNotEmpty) _oldPin = _oldPin.substring(0, _oldPin.length - 1);
      if (_step == 1 && _newPin.isNotEmpty) _newPin = _newPin.substring(0, _newPin.length - 1);
      if (_step == 2 && _confirmPin.isNotEmpty) _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปลี่ยนรหัส PIN สำเร็จ')),
        );
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

    String currentInput = _step == 0 ? _oldPin : (_step == 1 ? _newPin : _confirmPin);

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
                              color: active ? AppColors.primary : Theme.of(context).dividerColor,
                            ),
                          );
                        }),
                      ),
                      
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: const TextStyle(color: AppColors.error)),
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
                  child: Text(u.fullName.substring(0, 1), style: TextStyle(color: u.roleColor)),
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

  Future<void> _confirmReset(BuildContext context, WidgetRef ref, UserRecord targetUser) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการปลดล็อก PIN'),
        content: Text('คุณต้องการล้างรหัส PIN ของ "${targetUser.fullName}" ใช่หรือไม่?\nพนักงานจะต้องตั้งรหัส PIN ใหม่ในการอนุมัติครั้งถัดไป'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
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
          SnackBar(content: Text('ปลดล็อก PIN ของ ${targetUser.fullName} เรียบร้อยแล้ว')),
        );
      }
    }
  }
}
