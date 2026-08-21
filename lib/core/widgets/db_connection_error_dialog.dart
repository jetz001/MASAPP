import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../database/db_status_provider.dart';

class DbConnectionErrorDialog extends ConsumerWidget {
  const DbConnectionErrorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const DbConnectionErrorDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dbStatusProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 12,
        backgroundColor: theme.colorScheme.surface,
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'แจ้งเตือน: ไม่สามารถเชื่อมต่อฐานข้อมูลได้',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status.isNetworkPath
                              ? 'ขาดการเชื่อมต่อกับไดรฟ์เครือข่าย (Network Share)'
                              : 'เกิดปัญหาในการเปิดไฟล์ฐานข้อมูล',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Error explanation box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.shade900.withValues(alpha: 0.2)
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.red.shade800 : Colors.red.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.errorMessage ??
                          'ไม่สามารถเข้าถึงไฟล์ฐานข้อมูลได้ กรุณาตรวจสอบการเชื่อมต่อ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                        height: 1.4,
                      ),
                    ),
                    if (status.dbPath != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300),
                        ),
                        child: SelectableText(
                          status.dbPath!,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade300
                                : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Suggestions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined,
                        size: 18, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'คำแนะนำ: ตรวจสอบว่าเครื่องเซิร์ฟเวอร์เปิดอยู่, สาย LAN ต่อสนิท หรือฮาร์ดดิสก์/ไดรฟ์ปลายทางเสียบแน่นและเปิดแชร์โฟลเดอร์อยู่หรือไม่',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actions (Responsive Wrap)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.settings_rounded, size: 16),
                      label: const Text('ตั้งค่าฐานข้อมูลใหม่'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.go('/setup');
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.storage_rounded, size: 16),
                      label: const Text('สลับใช้ฐานข้อมูลในเครื่อง'),
                      onPressed: status.isRetrying
                          ? null
                          : () async {
                              await ref
                                  .read(dbStatusProvider.notifier)
                                  .switchToLocal();
                              if (context.mounted &&
                                  ref.read(dbStatusProvider).isConnected) {
                                Navigator.of(context).pop();
                                context.go('/dashboard');
                              }
                            },
                    ),
                    FilledButton.icon(
                      icon: status.isRetrying
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('ลองเชื่อมต่อใหม่'),
                      onPressed: status.isRetrying
                          ? null
                          : () async {
                              final success = await ref
                                  .read(dbStatusProvider.notifier)
                                  .retryConnect();
                              if (success && context.mounted) {
                                Navigator.of(context).pop();
                                context.go('/dashboard');
                              }
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
