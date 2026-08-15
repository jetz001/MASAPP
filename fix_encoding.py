# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('lib/features/line_balancing/line_balancing_screen.dart', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Since the file is already corrupted in the disk, reading it might keep the corruption.
# I should just recreate the file using Python string literal.
