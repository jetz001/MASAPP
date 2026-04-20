import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/auth/auth_provider.dart';
import '../theme/theme_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

/// App shell: sidebar + content area
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute;

  const AppShell({super.key, required this.child, required this.currentRoute});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sidebarExpanded = true;

  void _onThemeToggle(Offset offset) {
    ref.read(themeModeProvider.notifier).toggle();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            width: _sidebarExpanded ? 220 : 64,
            child: _Sidebar(
              expanded: _sidebarExpanded,
              currentRoute: widget.currentRoute,
              user: user,
              onToggle: () =>
                  setState(() => _sidebarExpanded = !_sidebarExpanded),
            ),
          ),

          // Vertical divider
          Container(
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),

          // Content
          Expanded(
            child: Column(
              children: [
                // Top bar
                _TopBar(
                  user: user,
                  sidebarExpanded: _sidebarExpanded,
                  onThemeToggle: _onThemeToggle,
                ),
                Container(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                // Page content
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem {
  final String label;
  final dynamic icon;
  final dynamic iconSelected;
  final String route;
  final List<String> roles; // empty = all roles

  const _NavItem({
    required this.label,
    required this.icon,
    required this.iconSelected,
    required this.route,
    this.roles = const [],
  });
}

const _navItems = [
  _NavItem(
    label: 'แดชบอร์ด',
    icon: HugeIcons.strokeRoundedDashboardCircle,
    iconSelected: HugeIcons.strokeRoundedDashboardCircle,
    route: '/dashboard',
  ),
  _NavItem(
    label: 'ทะเบียนเครื่องจักร',
    icon: HugeIcons.strokeRoundedLibrary,
    iconSelected: HugeIcons.strokeRoundedLibrary,
    route: '/machine-registry',
  ),
  _NavItem(
    label: 'แผนที่โรงงาน',
    icon: HugeIcons.strokeRoundedLocation01,
    iconSelected: HugeIcons.strokeRoundedLocation01,
    route: '/factory-layout',
  ),
  _NavItem(
    label: 'PM / AM',
    icon: HugeIcons.strokeRoundedCalendar03,
    iconSelected: HugeIcons.strokeRoundedCalendar03,
    route: '/pm-am',
  ),
  _NavItem(
    label: 'ใบสั่งงาน',
    icon: HugeIcons.strokeRoundedTask01,
    iconSelected: HugeIcons.strokeRoundedTask01,
    route: '/work-orders',
  ),
  _NavItem(
    label: 'ใบอนุญาตทำงาน',
    icon: HugeIcons.strokeRoundedAgreement01,
    iconSelected: HugeIcons.strokeRoundedAgreement01,
    route: '/work-permit',
    roles: ['safety', 'engineer', 'admin'],
  ),
  _NavItem(
    label: 'คลังอะไหล่',
    icon: HugeIcons.strokeRoundedArchive02,
    iconSelected: HugeIcons.strokeRoundedArchive02,
    route: '/spare-parts',
  ),
  _NavItem(
    label: 'วิเคราะห์ & AI',
    icon: HugeIcons.strokeRoundedAiMagic,
    iconSelected: HugeIcons.strokeRoundedAiMagic,
    route: '/analytics',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'ทีมช่าง',
    icon: HugeIcons.strokeRoundedUserGroup,
    iconSelected: HugeIcons.strokeRoundedUserGroup,
    route: '/workforce',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'จัดการผู้ใช้',
    icon: HugeIcons.strokeRoundedSquareLock02,
    iconSelected: HugeIcons.strokeRoundedSquareLock02,
    route: '/admin',
    roles: ['admin'],
  ),
  _NavItem(
    label: 'การตั้งค่า',
    icon: HugeIcons.strokeRoundedSettings01,
    iconSelected: HugeIcons.strokeRoundedSettings01,
    route: '/settings',
  ),
];

class _Sidebar extends ConsumerWidget {
  final bool expanded;
  final String currentRoute;
  final UserSession? user;
  final VoidCallback onToggle;

  const _Sidebar({
    required this.expanded,
    required this.currentRoute,
    required this.user,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final role = user?.role ?? '';

    return Container(
      color: colorScheme.surfaceContainerLow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // Logo area
                    SizedBox(
                      height: 60,
                      child: !expanded
                          ? Center(
                              child: IconButton(
                                icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedArrowRight01,
                                  size: 20,
                                ),
                                onPressed: onToggle,
                              ),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: SizedBox(
                                width: 220,
                                child: Row(
                                  children: [
                                    const SizedBox(width: 16),
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: const HugeIcon(
                                        icon: HugeIcons.strokeRoundedDashboardSquare01,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'MASAPP',
                                      style: AppTextStyles.titleLarge.copyWith(
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const HugeIcon(
                                        icon: HugeIcons.strokeRoundedArrowLeft01,
                                        size: 20,
                                      ),
                                      onPressed: onToggle,
                                      tooltip: 'ย่อ Sidebar',
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),

                    Container(height: 1, color: AppColors.divider),

                    // Nav items
                    Expanded(
                      child: Column(
                        children: [
                          for (final item in _navItems)
                            if (item.roles.isEmpty || item.roles.contains(role))
                              _NavTile(
                                item: item,
                                isSelected: currentRoute.startsWith(item.route),
                                expanded: expanded,
                              ),
                        ],
                      ),
                    ),

                    Container(height: 1, color: AppColors.divider),

                    // Logout at bottom
                    _NavTile(
                      item: const _NavItem(
                        label: 'ออกจากระบบ',
                        icon: HugeIcons.strokeRoundedLogout01,
                        iconSelected: HugeIcons.strokeRoundedLogout01,
                        route: '__logout',
                      ),
                      isSelected: false,
                      expanded: expanded,
                      onTap: () async {
                        await ref.read(authProvider.notifier).logout();
                      },
                      iconColor: AppColors.error,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NavTile extends ConsumerWidget {
  final _NavItem item;
  final bool isSelected;
  final bool expanded;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _NavTile({
    required this.item,
    required this.isSelected,
    required this.expanded,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: expanded ? '' : item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap:
                onTap ??
                () {
                  if (!isSelected) {
                    context.go(item.route);
                  }
                },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  width: 200, // Fixed width for navigation items to prevent overflow during sidebar animation
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: isSelected ? item.iconSelected : item.icon,
                        size: 20,
                        color:
                            iconColor ??
                            (isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant),
                      ),
                      if (expanded) ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            item.label,
                            style:
                                (isSelected
                                        ? AppTextStyles.titleSmall
                                        : AppTextStyles.bodySmall)
                                    .copyWith(
                                      color:
                                          iconColor ??
                                          (isSelected
                                              ? colorScheme.onSurface
                                              : colorScheme.onSurfaceVariant),
                                    ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatefulWidget {
  final UserSession? user;
  final bool sidebarExpanded;
  final Function(Offset) onThemeToggle;

  const _TopBar({
    this.user,
    required this.sidebarExpanded,
    required this.onThemeToggle,
  });

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.isMaximized().then((maximized) {
      if (!mounted) return;
      setState(() => _isMaximized = maximized);
    });
  }

  Future<void> _toggleMaximizeRestore() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (!mounted) return;
    setState(() => _isMaximized = !_isMaximized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DragToMoveArea(
      child: Container(
        height: 60,
        color: colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            // Breadcrumb placeholder
            Text(
              'ระบบบริหารจัดการซ่อมบำรุง',
              style: AppTextStyles.titleMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const Spacer(),

            // Theme toggle
            _ThemeToggleButton(onToggle: widget.onThemeToggle),

            const SizedBox(width: AppSpacing.sm),

            // Notification bell
            _TopBarButton(
              icon: HugeIcons.strokeRoundedNotification01,
              tooltip: 'การแจ้งเตือน',
              onTap: () {},
              badge: '3',
            ),

            const SizedBox(width: AppSpacing.sm),

            // User info chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primaryContainer,
                    child: Text(
                      (widget.user?.fullName ?? 'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user?.fullName ?? '-',
                        style: AppTextStyles.labelMedium,
                      ),
                      Text(
                        widget.user?.roleDisplayName ?? '-',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            _WindowControlButtons(
              isMaximized: _isMaximized,
              onMinimize: () => windowManager.minimize(),
              onMaximizeRestore: _toggleMaximizeRestore,
              onClose: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowControlButtons extends StatelessWidget {
  final bool isMaximized;
  final VoidCallback onMinimize;
  final VoidCallback onMaximizeRestore;
  final VoidCallback onClose;

  const _WindowControlButtons({
    required this.isMaximized,
    required this.onMinimize,
    required this.onMaximizeRestore,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _WindowButton(
          icon: Icons.minimize,
          tooltip: 'ย่อหน้าต่าง',
          onTap: onMinimize,
          iconColor: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        _WindowButton(
          icon: isMaximized ? Icons.crop_square : Icons.open_in_full,
          tooltip: isMaximized ? 'คืนขนาดหน้าต่าง' : 'ขยายหน้าต่าง',
          onTap: onMaximizeRestore,
          iconColor: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        _WindowButton(
          icon: Icons.close,
          tooltip: 'ปิดแอป',
          onTap: onClose,
          iconColor: AppColors.error,
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color iconColor;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: iconColor),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(32, 32),
        ),
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  final dynamic icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? badge;

  const _TopBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        children: [
          IconButton(
            icon: HugeIcon(
              icon: icon,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Toggle Button
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeToggleButton extends ConsumerWidget {
  final Function(Offset) onToggle;
  const _ThemeToggleButton({required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    return Tooltip(
      message: isDark ? 'สลับเป็น Light Mode' : 'สลับเป็น Dark Mode',
      child: Builder(
        builder: (ctx) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => RotationTransition(
                  turns: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: HugeIcon(
                  icon: isDark
                      ? HugeIcons.strokeRoundedSun01
                      : HugeIcons.strokeRoundedMoon02,
                  key: ValueKey(isDark),
                  size: 20,
                  color: isDark
                      ? const Color(0xFFFBBF24)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onPressed: () {
                final RenderBox box = ctx.findRenderObject() as RenderBox;
                final Offset offset = box.localToGlobal(
                  box.size.center(Offset.zero),
                );
                onToggle(offset);
              },
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          );
        },
      ),
    );
  }
}
