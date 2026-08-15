# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/core/navigation/app_router.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

insert_idx = -1
for i, line in enumerate(lines):
    if '// Workforce' in line:
        insert_idx = i
        break

if insert_idx != -1:
    new_route = """          // Line Balancing
          GoRoute(
            path: '/line_balancing',
            builder: (context, state) => const LineBalancingScreen(),
          ),
"""
    lines.insert(insert_idx, new_route)

# also add import
import_stmt = "import '../../features/line_balancing/line_balancing_screen.dart';\n"
lines.insert(24, import_stmt)

with codecs.open('lib/core/navigation/app_router.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)
print("Fixed app_router")

with codecs.open('lib/core/widgets/app_shell.dart', 'r', encoding='utf-8') as f:
    shell_lines = f.readlines()

shell_idx = -1
for i, line in enumerate(shell_lines):
    if "route: '/oee_logs'," in line:
        # find the end of this nav item
        pass
for i, line in enumerate(shell_lines):
    if "label: 'ทีมช่าง'," in line:
        shell_idx = i - 1
        break

if shell_idx != -1:
    new_nav = """  _NavItem(
    label: 'Line Balancing',
    icon: HugeIcons.strokeRoundedFlowSquare,
    iconSelected: HugeIcons.strokeRoundedFlowSquare,
    route: '/line_balancing',
    roles: ['engineer', 'executive', 'admin'],
  ),
"""
    shell_lines.insert(shell_idx, new_nav)
    with codecs.open('lib/core/widgets/app_shell.dart', 'w', encoding='utf-8') as f:
        f.writelines(shell_lines)
print("Fixed app_shell")
