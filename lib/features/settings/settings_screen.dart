import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../auth/auth_provider.dart';
import '../machine_intake/machine_provider.dart';
import '../machine_intake/widgets/pin_keypad.dart';
import '../admin/admin_screen.dart'; 
import '../../../core/theme/ui_scale_provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:window_manager/window_manager.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isAdmin = user?.isEngineerOrAbove ?? false;

    final tabs = [
      _SettingsTabItem(
        icon: Icons.business_outlined,
        label: 'ข้อมูลองค์กร',
        content: const _OrganizationInfoTab(),
      ),
      _SettingsTabItem(
        icon: Icons.description_outlined,
        label: 'ระบบเอกสาร',
        content: const _DocumentSystemTab(),
      ),
      _SettingsTabItem(
        icon: Icons.brush_outlined,
        label: 'การแสดงผล',
        content: const _DisplaySettingsTab(),
      ),
      _SettingsTabItem(
        icon: Icons.badge_outlined,
        label: 'รหัส PIN อนุมัติ',
        content: const _MyPinTab(),
      ),
      if (isAdmin)
        _SettingsTabItem(
          icon: Icons.lock_open_outlined,
          label: 'ปลดล็อก PIN พนักงาน',
          content: const _UnlockPinTab(),
        ),
    ];

    return Row(
      children: [
        // Sidebar Navigation
        Container(
          width: 250,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings_suggest_outlined, color: AppColors.primary, size: 24),
                        const SizedBox(width: AppSpacing.sm),
                        Text('การตั้งค่า', style: AppTextStyles.headlineMedium),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('จัดการระบบและองค์กร', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: tabs.length,
                  itemBuilder: (context, index) {
                    final item = tabs[index];
                    final isSelected = _selectedIndex == index;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      child: ListTile(
                        leading: Icon(
                          item.icon,
                          size: 20,
                          color: isSelected ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
                        onTap: () => setState(() => _selectedIndex = index),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        selected: isSelected,
                        selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Main Content
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: tabs[_selectedIndex].content,
          ),
        ),
      ],
    );
  }
}

class _SettingsTabItem {
  final IconData icon;
  final String label;
  final Widget content;
  _SettingsTabItem({required this.icon, required this.label, required this.content});
}

// ─── Tab: Organization Info ─────────────────────────────────────────────────

class _OrganizationInfoTab extends ConsumerStatefulWidget {
  const _OrganizationInfoTab();

  @override
  ConsumerState<_OrganizationInfoTab> createState() => _OrganizationInfoTabState();
}

class _OrganizationInfoTabState extends ConsumerState<_OrganizationInfoTab> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _taxIdCtrl;
  late TextEditingController _phoneCtrl;
  bool _isDirty = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider).valueOrNull;
    _nameCtrl = TextEditingController(text: settings?.get(AppSettingKeys.orgName) ?? '');
    _addressCtrl = TextEditingController(text: settings?.get(AppSettingKeys.orgAddress) ?? '');
    _taxIdCtrl = TextEditingController(text: settings?.get(AppSettingKeys.orgTaxId) ?? '');
    _phoneCtrl = TextEditingController(text: settings?.get(AppSettingKeys.orgPhone) ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _taxIdCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_isDirty) setState(() => _isDirty = true);
    if (_isSaved) setState(() => _isSaved = false);
  }

  Future<void> _save() async {
    final notifier = ref.read(appSettingsProvider.notifier);
    await notifier.updateSetting(AppSettingKeys.orgName, _nameCtrl.text);
    await notifier.updateSetting(AppSettingKeys.orgAddress, _addressCtrl.text);
    await notifier.updateSetting(AppSettingKeys.orgTaxId, _taxIdCtrl.text);
    await notifier.updateSetting(AppSettingKeys.orgPhone, _phoneCtrl.text);
    
    setState(() {
      _isDirty = false;
      _isSaved = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isSaved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (settings) {
        final logoBase64 = settings.get(AppSettingKeys.orgLogo);
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ข้อมูลองค์กร', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 4),
              Text('ข้อมูลนี้จะปรากฏในรายงาน PDF และส่วนต่างๆ ของแอป', style: AppTextStyles.bodySmall),
              const SizedBox(height: 32),

              _buildLogoSection(context, ref, logoBase64),
              const SizedBox(height: 32),

              _buildField(_nameCtrl, 'ชื่อบริษัท / องค์กร', Icons.business_rounded),
              _buildField(_addressCtrl, 'ที่อยู่สำนักงาน', Icons.location_on_rounded, maxLines: 3),
              _buildField(_taxIdCtrl, 'เลขประจำตัวผู้เสียภาษี', Icons.badge_rounded),
              _buildField(_phoneCtrl, 'เบอร์โทรศัพท์ติดต่อ', Icons.phone_rounded),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isDirty ? _save : null,
                  icon: Icon(_isSaved ? Icons.check_circle_outline : Icons.save_outlined),
                  label: Text(_isSaved ? 'บันทึกสำเร็จ' : 'บันทึกข้อมูลองค์กร'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDirty ? AppColors.primary : Colors.grey.withValues(alpha: 0.1),
                    foregroundColor: _isDirty ? Colors.white : Colors.grey,
                    elevation: _isDirty ? 2 : 0,
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        );
      },
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => _onChanged(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSection(BuildContext context, WidgetRef ref, String logoBase64) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: logoBase64.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(base64Decode(logoBase64), fit: BoxFit.contain),
                    )
                  : const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('โลโก้บริษัท', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 4),
                  Text('แนะนำไฟล์ PNG/JPG ขนาดไม่เกิน 500 KB', style: AppTextStyles.bodySmall),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickLogo(ref),
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: const Text('เปลี่ยนรูปภาพ'),
                      ),
                      if (logoBase64.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => ref.read(appSettingsProvider.notifier).updateSetting(AppSettingKeys.orgLogo, ''),
                          child: const Text('ลบรูปภาพ', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLogo(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final bytes = await result.files.single.xFile.readAsBytes();
      final base64String = base64Encode(bytes);
      await ref.read(appSettingsProvider.notifier).updateSetting(AppSettingKeys.orgLogo, base64String);
    }
  }
}

// ─── Tab: Document System ───────────────────────────────────────────────────

class _DocumentSystemTab extends ConsumerStatefulWidget {
  const _DocumentSystemTab();

  @override
  ConsumerState<_DocumentSystemTab> createState() => _DocumentSystemTabState();
}

class _DocumentSystemTabState extends ConsumerState<_DocumentSystemTab> {
  late TextEditingController _docRefCtrl;
  bool _isDirty = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider).valueOrNull;
    _docRefCtrl = TextEditingController(text: settings?.get(AppSettingKeys.docIntakeRef, defaultValue: 'FM-MA-001') ?? 'FM-MA-001');
  }

  @override
  void dispose() {
    _docRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(appSettingsProvider.notifier).updateSetting(AppSettingKeys.docIntakeRef, _docRefCtrl.text);
    setState(() {
      _isDirty = false;
      _isSaved = true;
    });
    // Reset saved state after a few seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isSaved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ระบบเอกสาร', style: AppTextStyles.headlineSmall),
          const SizedBox(height: 4),
          Text('ตั้งค่ารหัสควบคุมเอกสารประจำฟอร์มต่างๆ', style: AppTextStyles.bodySmall),
          const SizedBox(height: 32),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('แบบฟอร์มตรวจรับเครื่องจักร (Machine Intake)', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _docRefCtrl,
                    decoration: const InputDecoration(
                      labelText: 'รหัสควบคุมเอกสาร (Document Ref. Code)',
                      hintText: 'เช่น FM-MA-001',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => setState(() {
                      _isDirty = true;
                      _isSaved = false;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text('รหัสนี้จะปรากฏที่มุมขวาล่างของรายงาน PDF ทุกหน้า', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isDirty ? _save : null,
                      icon: Icon(_isSaved ? Icons.check_circle_outline : Icons.save_outlined),
                      label: Text(_isSaved ? 'บันทึกสำเร็จ' : 'บันทึกการเปลี่ยนแปลง'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isDirty ? AppColors.primary : Colors.grey.withValues(alpha: 0.1),
                        foregroundColor: _isDirty ? Colors.white : Colors.grey,
                        elevation: _isDirty ? 2 : 0,
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
}

// ─── Tab: My PIN (REFACTORED) ───────────────────────────────────────────────

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
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          itemCount: users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final u = users[index];
            return Card(
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

  Future<void> _confirmReset(BuildContext context, WidgetRef ref, UserRecord targetUser) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการปลดล็อก PIN'),
        content: Text(
          'คุณต้องการล้างรหัส PIN ของ "${targetUser.fullName}" ใช่หรือไม่?\nพนักงานจะต้องตั้งรหัส PIN ใหม่ในการอนุมัติครั้งถัดไป',
        ),
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
            subtitle: 'ปรับขนาดของตัวอักษรและองค์ประกอบต่างๆ ในแอปให้เล็กลงหรือใหญ่ขึ้น',
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
                      Text('ปัจจุบัน: ${(scale * 100).toInt()}%', style: AppTextStyles.labelMedium),
                      TextButton(
                        onPressed: () => ref.read(uiScaleProvider.notifier).setScale(1.0),
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
            subtitle: 'เลือกขนาดหน้าต่างมาตรฐานหรือปรับตามความละเอียดจอ',
            icon: Icons.aspect_ratio,
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                _buildWindowSizeButton(context, 'XGA 1024x768', const Size(1024, 768)),
                _buildWindowSizeButton(context, 'SXGA 1280x1024', const Size(1280, 1024)),
                _buildWindowSizeButton(context, 'WXGA+ 1440x900', const Size(1440, 900)),
                _buildWindowSizeButton(context, 'Full HD 1920x1080', const Size(1920, 1080)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required String subtitle, required dynamic icon, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            icon is IconData ? Icon(icon, size: 20, color: AppColors.primary) : HugeIcon(icon: icon, size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTextStyles.titleLarge),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.lg),
        child,
      ],
    );
  }

  Widget _buildWindowSizeButton(BuildContext context, String label, Size size) {
    return ElevatedButton(
      onPressed: () async => await windowManager.setSize(size),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      child: Text(label),
    );
  }
}
