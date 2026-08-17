# -*- coding: utf-8 -*-
import codecs

def remove_bom(path):
    with open(path, 'rb') as f:
        content = f.read()
    if content.startswith(codecs.BOM_UTF8):
        content = content[3:]
        with open(path, 'wb') as f:
            f.write(content)
        print("Removed BOM from", path)

import glob
import os
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            remove_bom(os.path.join(root, f))
