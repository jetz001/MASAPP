# -*- coding: utf-8 -*-
import codecs

path = 'lib/features/auth/db_setup_screen.dart'
with codecs.open(path, 'r', 'utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_ui = """                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pathCtrl,
                              style: AppTextStyles.bodyMedium,"""

new_ui = """                      // --- NEW FIELDS ---
                      Text('ชื่อบริษัท / องค์กร', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _companyCtrl,
                        style: AppTextStyles.bodyMedium,
                        decoration: const InputDecoration(hintText: 'โรงงานตัวอย่าง จำกัด', prefixIcon: Icon(Icons.business)),
                      ),
                      const SizedBox(height: 20),

                      Text('ชื่อผู้ใช้งาน Admin', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _adminUsernameCtrl,
                        style: AppTextStyles.bodyMedium,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.person)),
                        validator: (v) => v == null || v.isEmpty ? 'กรุณาระบุ Username' : null,
                      ),
                      const SizedBox(height: 20),

                      Text('รหัสผ่าน Admin', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _adminPassCtrl,
                        style: AppTextStyles.bodyMedium,
                        obscureText: true,
                        decoration: const InputDecoration(hintText: 'ปล่อยว่างหากต้องการใช้รหัสผ่านตั้งต้น', prefixIcon: Icon(Icons.lock)),
                      ),
                      const SizedBox(height: 20),

                      Text('Serial Key / License (ถ้ามี)', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _serialKeyCtrl,
                        style: AppTextStyles.bodyMedium,
                        decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX-XXXX', prefixIcon: Icon(Icons.key)),
                      ),
                      const SizedBox(height: 40),
                      // --- END NEW FIELDS ---
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pathCtrl,
                              style: AppTextStyles.bodyMedium,"""

text = text.replace(old_ui, new_ui)

with codecs.open(path, 'w', 'utf-8') as f:
    f.write(text)
