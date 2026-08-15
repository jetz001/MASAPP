# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/core/navigation/app_router.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

out_lines = []
for line in lines:
    out_lines.append(line)
    if "path: '/analytics'," in line:
        # Find where this route block ends
        pass

# Instead of looking for lines, let's just insert it before `// Workforce`
insert_idx = -1
for i, line in enumerate(lines):
    if '// Workforce' in line:
        insert_idx = i
        break

if insert_idx != -1:
    new_route = """          // OEE Logs
          GoRoute(
            path: '/oee_logs',
            builder: (context, state) => const OeeLogsScreen(),
          ),
"""
    lines.insert(insert_idx, new_route)
    with codecs.open('lib/core/navigation/app_router.dart', 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("Fixed router correctly")
else:
    print("Could not find // Workforce")
