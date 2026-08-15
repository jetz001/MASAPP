# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/core/widgets/app_shell.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_nav = """      _NavItem(
        label: 'วิเคราะห์ & AI',
        route: '/analytics',
        icon: HugeIcons.strokeRoundedAnalytics01,
      ),"""

new_nav = """      _NavItem(
        label: 'วิเคราะห์ & AI',
        route: '/analytics',
        icon: HugeIcons.strokeRoundedAnalytics01,
      ),
      _NavItem(
        label: 'บันทึก OEE',
        route: '/oee_logs',
        icon: HugeIcons.strokeRoundedActivity01,
      ),"""
content = content.replace(old_nav, new_nav)

with codecs.open('lib/core/widgets/app_shell.dart', 'w', encoding='utf-8') as f:
    f.write(content)

with codecs.open('lib/core/navigation/app_router.dart', 'r', encoding='utf-8') as f:
    content2 = f.read()

import_line = "import '../../features/analytics/analytics_dashboard_screen.dart';"
new_import = import_line + "\nimport '../../features/oee_logs/oee_logs_screen.dart';"
content2 = content2.replace(import_line, new_import)

old_route = """        GoRoute(
          path: 'analytics',
          builder: (context, state) => const AnalyticsDashboardScreen(),
        ),"""
new_route = """        GoRoute(
          path: 'analytics',
          builder: (context, state) => const AnalyticsDashboardScreen(),
        ),
        GoRoute(
          path: 'oee_logs',
          builder: (context, state) => const OeeLogsScreen(),
        ),"""
content2 = content2.replace(old_route, new_route)

with codecs.open('lib/core/navigation/app_router.dart', 'w', encoding='utf-8') as f:
    f.write(content2)
print("Updated router and shell")
