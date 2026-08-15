# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('lib/core/navigation/app_router.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_route = r"""          GoRoute\(
            path: '/analytics',
            builder: \(context, state\) => const AnalyticsDashboardScreen\(\),
          \),"""

new_route = """          GoRoute(
            path: '/analytics',
            builder: (context, state) => const AnalyticsDashboardScreen(),
          ),
          
          GoRoute(
            path: '/oee_logs',
            builder: (context, state) => const OeeLogsScreen(),
          ),"""

content = re.sub(old_route, new_route, content)

with codecs.open('lib/core/navigation/app_router.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed app_router")
