# -*- coding: utf-8 -*-
import codecs
import os

def remove_ufeff(path):
    with codecs.open(path, 'r', 'utf-8') as f:
        content = f.read()
    if u'\ufeff' in content:
        content = content.replace(u'\ufeff', '')
        with codecs.open(path, 'w', 'utf-8') as f:
            f.write(content)
        print("Removed U+FEFF from", path)

for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            remove_ufeff(os.path.join(root, f))
