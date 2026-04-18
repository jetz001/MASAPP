import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';

class PinKeypad extends StatelessWidget {
  final Function(String) onKeyTap;
  final VoidCallback onBackspace;
  final Color? activeColor;

  const PinKeypad({
    super.key,
    required this.onKeyTap,
    required this.onBackspace,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((key) => _KeyButton(
                label: key,
                onTap: () => onKeyTap(key),
                color: activeColor,
              )).toList(),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 64, height: 64), // Spacer
            _KeyButton(
              label: '0',
              onTap: () => onKeyTap('0'),
              color: activeColor,
            ),
            _KeyButton(
              icon: Icons.backspace_outlined,
              onTap: onBackspace,
              isSecondary: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isSecondary;
  final Color? color;

  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.isSecondary = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: isSecondary 
          ? colorScheme.surfaceContainerHigh 
          : (color?.withValues(alpha: 0.1) ?? colorScheme.primary.withValues(alpha: 0.08)),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isSecondary ? colorScheme.onSurface : (color ?? colorScheme.primary),
                    ),
                  )
                : Icon(
                    icon,
                    size: 24,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}
