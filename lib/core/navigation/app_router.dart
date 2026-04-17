import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/auth_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/db_setup_screen.dart';
import '../../features/machine_intake/machine_intake_list_screen.dart';
import '../../features/machine_intake/machine_intake_form_screen.dart';
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
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPlaceholder(),
          ),
          GoRoute(
            path: '/machine-intake',
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
          GoRoute(
            path: '/factory-layout',
            builder: (context, state) => const PlaceholderScreen(title: 'แผนที่โรงงาน', module: 'factory_layout'),
          ),
          GoRoute(
            path: '/machine-registry',
            builder: (context, state) => const PlaceholderScreen(title: 'ทะเบียนเครื่องจักร', module: 'machine_registry'),
          ),
          GoRoute(
            path: '/pm-am',
            builder: (context, state) => const PlaceholderScreen(title: 'PM / AM', module: 'pm_am'),
          ),
          GoRoute(
            path: '/work-orders',
            builder: (context, state) => const PlaceholderScreen(title: 'ใบสั่งงานซ่อมบำรุง', module: 'work_orders'),
          ),
          GoRoute(
            path: '/work-permit',
            builder: (context, state) => const PlaceholderScreen(title: 'ใบอนุญาตทำงาน', module: 'work_permit'),
          ),
          GoRoute(
            path: '/spare-parts',
            builder: (context, state) => const PlaceholderScreen(title: 'คลังอะไหล่', module: 'spare_parts'),
          ),
          GoRoute(
            path: '/analytics',
            builder: (context, state) => const PlaceholderScreen(title: 'วิเคราะห์ & AI', module: 'analytics'),
          ),
          GoRoute(
            path: '/workforce',
            builder: (context, state) => const PlaceholderScreen(title: 'ทีมช่าง', module: 'workforce'),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const PlaceholderScreen(title: 'จัดการผู้ใช้งาน', module: 'admin'),
          ),
        ],
      ),
    ],
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder screens for unbuilt modules
// ─────────────────────────────────────────────────────────────────────────────
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String module;
  const PlaceholderScreen({super.key, required this.title, required this.module});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_rounded, size: 64,
              color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Colors.white70)),
          const SizedBox(height: 8),
          Text('กำลังพัฒนา — Phase 2+',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }
}

class DashboardPlaceholder extends ConsumerWidget {
  const DashboardPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.dashboard_rounded, size: 64,
            color: Color(0xFF2563EB)),
        const SizedBox(height: 16),
        Text('ยินดีต้อนรับ, ${user?.fullName ?? ''}',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text('MASAPP — Maintenance Super App',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.white54)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => context.go('/machine-intake'),
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('เริ่มต้นด้วย การรับเครื่องจักร'),
        ),
      ]),
    );
  }
}
