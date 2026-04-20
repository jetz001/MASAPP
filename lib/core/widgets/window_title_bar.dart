import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowTitleBar extends StatefulWidget {
  final Color? color;
  final Color? iconColor;
  final String? title;

  const WindowTitleBar({
    super.key,
    this.color,
    this.iconColor,
    this.title,
  });

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  Widget build(BuildContext context) {
    final defaultIconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: 38,
        color: widget.color ?? Colors.transparent,
        child: Row(
        children: [
          // Drag Area (Title/Logo)
          Expanded(
            child: DragToMoveArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                child: widget.title != null
                    ? Text(
                        widget.title!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: (widget.iconColor ?? defaultIconColor).withValues(alpha: 0.6),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Window Buttons
          _WindowButton(
            icon: Icons.remove_rounded,
            onPressed: () => windowManager.minimize(),
            iconColor: widget.iconColor ?? defaultIconColor,
          ),
          _WindowButton(
            icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            size: 16,
            onPressed: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
              _checkMaximized();
            },
            iconColor: widget.iconColor ?? defaultIconColor,
          ),
          _WindowButton(
            icon: Icons.close_rounded,
            isClose: true,
            onPressed: () => windowManager.close(),
            iconColor: widget.iconColor ?? defaultIconColor,
          ),
        ],
      ),
    ),);
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  final double size;
  final Color iconColor;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
    this.size = 20,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      hoverColor: isClose ? Colors.red : Colors.black12,
      child: SizedBox(
        width: 46,
        height: 38,
        child: Icon(
          icon,
          size: size,
          color: iconColor,
        ),
      ),
    );
  }
}
