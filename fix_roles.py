import codecs

with codecs.open('lib/core/widgets/app_shell.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

out = []
last_was_roles = False
for line in lines:
    if "roles: ['engineer'" in line:
        if last_was_roles:
            continue
        last_was_roles = True
    else:
        last_was_roles = False
    out.append(line)

with codecs.open('lib/core/widgets/app_shell.dart', 'w', encoding='utf-8') as f:
    f.writelines(out)
print("Cleaned up roles")
