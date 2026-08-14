import os
import codecs

dirs = ['lib']
for d in dirs:
    for root, _, files in os.walk(d):
        for f in files:
            if f.endswith('.dart'):
                p = os.path.join(root, f)
                try:
                    with open(p, 'rb') as file:
                        content = file.read()
                        content.decode('utf-8')
                except UnicodeDecodeError:
                    print(f'Fixing {p}')
                    try:
                        # Try decoding with TIS-620 or cp1252 (powershell Add-Content might use system encoding)
                        text = content.decode('tis-620')
                        with open(p, 'w', encoding='utf-8') as file:
                            file.write(text)
                        print(f'Fixed {p}')
                    except Exception as e:
                        print(f'Failed to fix {p}: {e}')
