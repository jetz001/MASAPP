import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_colors.dart';

class HoverImageTooltip extends StatelessWidget {
  final String? imagePath;

  const HoverImageTooltip({super.key, this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Tooltip(
      preferBelow: false,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      richMessage: WidgetSpan(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            File(imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('ไม่พบรูปภาพ', style: TextStyle(color: AppColors.error)),
            ),
          ),
        ),
      ),
      child: IconButton(
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 16, color: AppColors.primary),
        onPressed: () {},
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: '',
      ),
    );
  }
}
