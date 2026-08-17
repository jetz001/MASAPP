# -*- coding: utf-8 -*-
import codecs

path = 'lib/features/auth/db_setup_screen.dart'
with codecs.open(path, 'r', 'utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_db_init = """          final adminUser = _adminUsernameCtrl.text.trim();
          final adminPass = _adminPassCtrl.text;
          if (adminUser.isNotEmpty && adminPass.isNotEmpty) {
            // Need to hash password. For now, we will use a quick SHA256 if possible, but dart:convert handles base64, crypto is needed.
            // Since we don't have crypto import here, we rely on the backend. Actually, wait! We need `crypto` for SHA256.
          }"""

new_db_init = """          final adminUser = _adminUsernameCtrl.text.trim();
          final adminPass = _adminPassCtrl.text;
          if (adminUser.isNotEmpty && adminPass.isNotEmpty) {
            final hashedPass = CryptoUtils.hashPassword(adminPass);
            await txn.execute(
              "UPDATE users SET username = ?, password_hash = ? WHERE role = 'admin'",
              [adminUser, hashedPass]
            );
          }"""

text = text.replace(old_db_init, new_db_init)

if "import '../../core/utils/crypto_utils.dart';" not in text:
    text = text.replace("import '../../core/config/app_config.dart';", "import '../../core/config/app_config.dart';\nimport '../../core/utils/crypto_utils.dart';")

with codecs.open(path, 'w', 'utf-8') as f:
    f.write(text)

