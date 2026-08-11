import fitz
import json
import re

pdf_path = r'C:\Users\Boss-QA\.gemini\antigravity\brain\9baa7aba-559a-46f3-9268-2445c6a68eb8\.user_uploaded\media_1786424553868.pdf'
doc = fitz.open(pdf_path)

all_text = ""
for page in doc:
    all_text += page.get_text() + "\n---PAGE---\n"

with open('d:/DEV/MASAPP/scripts/pdf_extract.txt', 'w', encoding='utf-8') as f:
    f.write(all_text)
