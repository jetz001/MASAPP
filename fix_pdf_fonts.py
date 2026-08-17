# -*- coding: utf-8 -*-
import codecs
import os
import glob

def fix_fonts(directory):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                path = os.path.join(root, file)
                try:
                    with codecs.open(path, 'r', 'utf-8') as f:
                        content = f.read()
                except:
                    continue
                
                if 'PdfGoogleFonts.sarabun' in content:
                    # We need to make sure rootBundle is imported
                    if "import 'package:flutter/services.dart'" not in content:
                        content = "import 'package:flutter/services.dart';\n" + content
                    
                    content = content.replace('await PdfGoogleFonts.sarabunRegular()', "pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf'))")
                    content = content.replace('await PdfGoogleFonts.sarabunBold()', "pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf'))")
                    content = content.replace('await PdfGoogleFonts.sarabunItalic()', "pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf'))") # we don't have italic
                    content = content.replace('await PdfGoogleFonts.sarabunBoldItalic()', "pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf'))") # we don't have bold italic
                    
                    with codecs.open(path, 'w', 'utf-8') as f:
                        f.write(content)
                    print(f'Fixed {path}')

fix_fonts('lib')
