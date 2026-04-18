import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/auth_provider.dart';
import '../machine_provider.dart';
import '../machine_models.dart';
import 'pin_keypad.dart';

class ApprovalDialog extends ConsumerStatefulWidget {
  final String machineId;
  final String title;

  const ApprovalDialog({
    super.key,
    required this.machineId,
    required this.title,
  });

  @override
  ConsumerState<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends ConsumerState<ApprovalDialog> {
  String _pin = '';
  String? _error;
  bool _loading = false;
  bool _isReject = false;
  final _reasonCtrl = TextEditingController();

  void _onKeyTap(String key) {
    if (_pin.length < 4) {
      setState(() {
        _pin += key;
        _error = null;
      });
      
      // Auto-submit when length reaches 4
      if (_pin.length == 4) {
        Future.delayed(const Duration(milliseconds: 200), () => _process(!_isReject));
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      });
    }
  }

  Future<void> _process(bool approved) async {
    if (_pin.length < 4) {
      setState(() => _error = 'กรุณาใส่รหัส PIN 4 หลัก');
      return;
    }

    if (!approved && _reasonCtrl.text.isEmpty) {
      setState(() => _error = 'กรุณาระบุเหตุผลที่ปฏิเสธ');
      return;
    }

    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider);
      final repo = ref.read(machineRepositoryProvider);

      if (user == null) return;

      final pinValid = await repo.verifyApprovalPin(user.userId, _pin);
      if (!pinValid) {
        setState(() {
          _pin = '';
          _error = 'รหัส PIN ไม่ถูกต้อง';
          _loading = false;
        });
        return;
      }

      // Perform the update
      // For this simple intake flow, we assume we are approving Stage 3
      await repo.updateHandoverStage(
        machineId: widget.machineId,
        stage: HandoverStage.stage3,
        status: approved ? HandoverStatus.approved : HandoverStatus.failed,
        performedBy: user.userId,
        notes: _reasonCtrl.text,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  _isReject ? Icons.cancel_outlined : Icons.verified_user_outlined,
                  color: _isReject ? AppColors.error : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  _isReject ? 'การปฏิเสธ (Reject)' : 'การอนุมัติ (Approve)',
                  style: AppTextStyles.headlineMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              'กรุณาใส่รหัส PIN เพื่อยืนยันการ${_isReject ? "ปฏิเสธ" : "อนุมัติ"}',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 24),
            
            // PIN Display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final hasChar = index < _pin.length;
                return Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasChar 
                      ? (_isReject ? AppColors.error : AppColors.primary) 
                      : Theme.of(context).dividerColor,
                  ),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            
            const SizedBox(height: 32),
            
            if (_isReject) ...[
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'เหตุผลที่ปฏิเสธ *',
                  hintText: 'กรุณาระบุสาเหตุที่ตรวจรับไม่ผ่าน',
                ),
                maxLines: 2,
                autofocus: true,
              ),
              const SizedBox(height: 24),
            ],

            // Pin Keypad (ATM Style)
            PinKeypad(
              onKeyTap: _onKeyTap,
              onBackspace: _onBackspace,
              activeColor: _isReject ? AppColors.error : AppColors.primary,
            ),

            const SizedBox(height: 32),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isReject = !_isReject),
                    child: Text(_isReject ? 'ต้องการอนุมัติ' : 'ต้องการปฏิเสธ'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _process(!_isReject),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isReject ? AppColors.error : AppColors.primary,
                    ),
                    child: _loading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isReject ? 'ยืนยันปฏิเสธ' : 'ยืนยันอนุมัติ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
