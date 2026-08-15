# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/core/widgets/app_shell.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the duplicate block
bad_block = """    route: '/analytics',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'บันทึก OEE',
    icon: HugeIcons.strokeRoundedActivity01,
    iconSelected: HugeIcons.strokeRoundedActivity01,
    route: '/oee_logs',
    roles: ['engineer', 'executive', 'admin'],
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'ทีมช่าง',"""

good_block = """    route: '/analytics',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'บันทึก OEE',
    icon: HugeIcons.strokeRoundedActivity01,
    iconSelected: HugeIcons.strokeRoundedActivity01,
    route: '/oee_logs',
    roles: ['engineer', 'executive', 'admin'],
  ),
  _NavItem(
    label: 'ทีมช่าง',"""

content = content.replace(bad_block, good_block)

with codecs.open('lib/core/widgets/app_shell.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed app_shell duplicate")
