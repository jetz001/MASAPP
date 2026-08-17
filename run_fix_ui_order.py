# -*- coding: utf-8 -*-
import codecs

path = 'lib/features/auth/db_setup_screen.dart'
with codecs.open(path, 'r', 'utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_ui = """                      Text(
                        'ที่อยู่ไฟล์ฐานข้อมูล (.db)',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // --- NEW FIELDS ---"""

new_ui = """                      // --- NEW FIELDS ---"""

text = text.replace(old_ui, new_ui)

old_ui2 = """                      // --- END NEW FIELDS ---
                      
                      Row("""

new_ui2 = """                      // --- END NEW FIELDS ---
                      Text(
                        'ที่อยู่ไฟล์ฐานข้อมูล (.db)',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row("""

text = text.replace(old_ui2, new_ui2)

with codecs.open(path, 'w', 'utf-8') as f:
    f.write(text)
