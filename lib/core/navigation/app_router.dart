import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/db_setup_screen.dart';
import '../../features/machine_intake/machine_intake_list_screen.dart';
import '../../features/machine_intake/machine_intake_form_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/work_orders/work_order_list_screen.dart';
import '../../features/spare_parts/spare_parts_screen.dart';
import '../../features/pm_am/pm_am_screen.dart';
import '../../features/work_permit/work_permit_screen.dart';
import '../../features/workforce/workforce_screen.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/factory_layout/factory_layout_screen.dart';
import '../../features/factory_layout/layout_list_screen.dart';
import '../../features/analytics/analytics_dashboard_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    redirect: (context, state) async {
      final isLoggedIn = authState != null;
      final isLoginRoute = state.matchedLocation.startsWith('/login');
      final isSetupRoute = state.matchedLocation.startsWith('/setup');

      if (isSetupRoute) return null;
      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/dashboard';
      return null;
    },
    routes: [
      // Root redirect
      GoRoute(
        path: '/',
        redirect: (_, _) => '/dashboard',
      ),

      // DB Setup (first launch)
      GoRoute(
        path: '/setup',
        builder: (context, state) => DbSetupScreen(
          onConnected: () => context.go('/login'),
        ),
      ),

      // Login
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          onLoggedIn: () => context.go('/dashboard'),
        ),
      ),

      // Main shell with sidebar
      ShellRoute(
        builder: (context, state, child) => AppShell(
          currentRoute: state.matchedLocation,
          child: child,
        ),
        routes: [
          // Dashboard
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),

          // Machine Registry
          GoRoute(
            path: '/machine-registry',
            builder: (context, state) => const MachineIntakeListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const MachineIntakeFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => MachineIntakeFormScreen(
                  machineId: state.pathParameters['id'],
                ),
              ),
            ],
          ),

          // Factory Layout
          GoRoute(
            path: '/factory-layout',
            builder: (context, state) => const FactoryLayoutScreen(),
            routes: [
              GoRoute(
                path: 'management',
                builder: (context, state) => const LayoutListScreen(),
              ),
            ],
          ),

          // PM / AM
          GoRoute(
            path: '/pm-am',
            builder: (context, state) => const PmAmListScreen(),
          ),

          // Work Orders
          GoRoute(
            path: '/work-orders',
            builder: (context, state) => const WorkOrderListScreen(),
          ),

          // Work Permit
          GoRoute(
            path: '/work-permit',
            builder: (context, state) => const WorkPermitScreen(),
          ),

          // Spare Parts
          GoRoute(
            path: '/spare-parts',
            builder: (context, state) => const SparePartsListScreen(),
          ),

          // Analytics (placeholder)
          GoRoute(
            path: '/analytics',
            builder: (context, state) => const AnalyticsDashboardScreen(),
          ),

          // Workforce
          GoRoute(
            path: '/workforce',
            builder: (context, state) => const WorkforceScreen(),
          ),

          // Admin
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminScreen(),
          ),

          // Settings
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder (for modules not yet fully implemented)
// ─────────────────────────────────────────────────────────────────────────────

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String module;
  const PlaceholderScreen(
      {super.key, required this.title, required this.module});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_rounded,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          Text('กำลังพัฒนา',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}
