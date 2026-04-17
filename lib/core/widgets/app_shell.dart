import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

/// App shell: sidebar + content area
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute;

  const AppShell({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sidebarExpanded = true;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
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
          Container(width: 1, color: AppColors.divider),

          // Content
          Expanded(
            child: Column(
              children: [
                // Top bar
                _TopBar(user: user, sidebarExpanded: _sidebarExpanded),
                Container(height: 1, color: AppColors.divider),
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
  final IconData icon;
  final IconData iconSelected;
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
    icon: Icons.dashboard_outlined,
    iconSelected: Icons.dashboard_rounded,
    route: '/dashboard',
  ),
  _NavItem(
    label: 'รับเครื่องจักร',
    icon: Icons.add_business_outlined,
    iconSelected: Icons.add_business_rounded,
    route: '/machine-intake',
  ),
  _NavItem(
    label: 'แผนที่โรงงาน',
    icon: Icons.map_outlined,
    iconSelected: Icons.map_rounded,
    route: '/factory-layout',
  ),
  _NavItem(
    label: 'ทะเบียนเครื่องจักร',
    icon: Icons.precision_manufacturing_outlined,
    iconSelected: Icons.precision_manufacturing_rounded,
    route: '/machine-registry',
  ),
  _NavItem(
    label: 'PM / AM',
    icon: Icons.build_circle_outlined,
    iconSelected: Icons.build_circle_rounded,
    route: '/pm-am',
  ),
  _NavItem(
    label: 'ใบสั่งงาน',
    icon: Icons.assignment_outlined,
    iconSelected: Icons.assignment_rounded,
    route: '/work-orders',
  ),
  _NavItem(
    label: 'ใบอนุญาตทำงาน',
    icon: Icons.verified_user_outlined,
    iconSelected: Icons.verified_user_rounded,
    route: '/work-permit',
    roles: ['safety', 'engineer', 'admin'],
  ),
  _NavItem(
    label: 'คลังอะไหล่',
    icon: Icons.inventory_2_outlined,
    iconSelected: Icons.inventory_2_rounded,
    route: '/spare-parts',
  ),
  _NavItem(
    label: 'วิเคราะห์ & AI',
    icon: Icons.auto_graph_outlined,
    iconSelected: Icons.auto_graph_rounded,
    route: '/analytics',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'ทีมช่าง',
    icon: Icons.groups_outlined,
    iconSelected: Icons.groups_rounded,
    route: '/workforce',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'จัดการผู้ใช้',
    icon: Icons.manage_accounts_outlined,
    iconSelected: Icons.manage_accounts_rounded,
    route: '/admin',
    roles: ['admin'],
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
    final role = user?.role ?? '';

    return Container(
      color: AppColors.bgSidebar,
      child: Column(
        children: [
          // Logo area
          SizedBox(
            height: 60,
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
                  child: const Icon(
                    Icons.precision_manufacturing_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  Text('MASAPP',
                      style: AppTextStyles.titleLarge
                          .copyWith(color: AppColors.textPrimary)),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(
                    expanded
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: onToggle,
                  tooltip: expanded ? 'ย่อ Sidebar' : 'ขยาย Sidebar',
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),

          Container(height: 1, color: AppColors.divider),

          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
              icon: Icons.logout_rounded,
              iconSelected: Icons.logout_rounded,
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
    return Tooltip(
      message: expanded ? '' : item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap ??
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
                    ? AppColors.navSelected
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? item.iconSelected : item.icon,
                    size: 20,
                    color: iconColor ??
                        (isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        item.label,
                        style: (isSelected
                                ? AppTextStyles.titleSmall
                                : AppTextStyles.bodySmall)
                            .copyWith(
                          color: iconColor ??
                              (isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final UserSession? user;
  final bool sidebarExpanded;

  const _TopBar({this.user, required this.sidebarExpanded});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Row(
        children: [
          // Breadcrumb placeholder
          Text('ระบบบริหารจัดการซ่อมบำรุง',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.textSecondary)),

          const Spacer(),

          // Notification bell
          _TopBarButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'การแจ้งเตือน',
            onTap: () {},
            badge: '3',
          ),

          const SizedBox(width: AppSpacing.sm),

          // User info chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primaryContainer,
                  child: Text(
                    (user?.fullName ?? 'U').substring(0, 1).toUpperCase(),
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.fullName ?? '-',
                      style: AppTextStyles.labelMedium,
                    ),
                    Text(
                      user?.roleDisplayName ?? '-',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  final IconData icon;
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
            icon: Icon(icon, size: 22, color: AppColors.textSecondary),
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.bgElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: const BorderSide(color: AppColors.border),
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
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
