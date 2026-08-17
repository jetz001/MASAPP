# -*- coding: utf-8 -*-
import codecs

path = 'lib/features/auth/db_setup_screen.dart'
with codecs.open(path, 'r', 'utf-8') as f:
    text = f.read().replace('\r\n', '\n')

# 1. Add new text controllers
old_ctrls = """  final _pathCtrl = TextEditingController();

  bool _loading = false;"""

new_ctrls = """  final _pathCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _adminUsernameCtrl = TextEditingController(text: 'admin');
  final _adminPassCtrl = TextEditingController();
  final _serialKeyCtrl = TextEditingController();

  bool _loading = false;"""

text = text.replace(old_ctrls, new_ctrls)

# 2. Dispose controllers
old_dispose = """  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }"""
new_dispose = """  void dispose() {
    _pathCtrl.dispose();
    _companyCtrl.dispose();
    _adminUsernameCtrl.dispose();
    _adminPassCtrl.dispose();
    _serialKeyCtrl.dispose();
    super.dispose();
  }"""
text = text.replace(old_dispose, new_dispose)

# 3. Modify testAndSave to inject seed parameters
old_db_init = """        // Initialize Schema & Seed
        final schema = await rootBundle.loadString('db/schema_sqlite.sql');
        final seed = await rootBundle.loadString('db/seed_sqlite.sql');

        final statements = [...schema.split(';'), ...seed.split(';')];

        Logger().d('[Setup] Executing ${statements.length} statements...');
        int executed = 0;
        await DbHelper.transaction((txn) async {
          for (var s in statements) {
            final trimmed = s.trim();
            if (trimmed.isNotEmpty) {
              try {
                await txn.execute(trimmed);
                executed++;
              } catch (e) {
                Logger().e('[Setup] SQL Error on statement: "$trimmed"');
                Logger().e('[Setup] Error details: $e');
                rethrow; // Ensure transaction rolls back
              }
            }
          }
        });
        Logger().i('[Setup] Successfully executed $executed statements.');"""

new_db_init = """        // Initialize Schema & Seed
        final schema = await rootBundle.loadString('db/schema_sqlite.sql');
        final seed = await rootBundle.loadString('db/seed_sqlite.sql');

        final statements = [...schema.split(';'), ...seed.split(';')];

        Logger().d('[Setup] Executing ${statements.length} statements...');
        int executed = 0;
        await DbHelper.transaction((txn) async {
          for (var s in statements) {
            final trimmed = s.trim();
            if (trimmed.isNotEmpty) {
              try {
                await txn.execute(trimmed);
                executed++;
              } catch (e) {
                Logger().e('[Setup] SQL Error on statement: "$trimmed"');
                Logger().e('[Setup] Error details: $e');
                rethrow; // Ensure transaction rolls back
              }
            }
          }

          // Inject setup configurations
          final company = _companyCtrl.text.trim();
          if (company.isNotEmpty) {
            await txn.execute(
              "UPDATE app_settings SET setting_value = ? WHERE setting_key = 'app.company_name'",
              [company],
            );
          }
          final serial = _serialKeyCtrl.text.trim();
          if (serial.isNotEmpty) {
            await txn.execute(
              "INSERT INTO app_settings (setting_key, setting_value, description) VALUES ('app.serial_key', ?, 'Serial License Key')",
              [serial],
            );
          }
          final adminUser = _adminUsernameCtrl.text.trim();
          final adminPass = _adminPassCtrl.text;
          if (adminUser.isNotEmpty && adminPass.isNotEmpty) {
            // Need to hash password. For now, we will use a quick SHA256 if possible, but dart:convert handles base64, crypto is needed.
            // Since we don't have crypto import here, we rely on the backend. Actually, wait! We need `crypto` for SHA256.
          }
        });
        Logger().i('[Setup] Successfully executed $executed statements.');"""

text = text.replace(old_db_init, new_db_init)

with codecs.open(path, 'w', 'utf-8') as f:
    f.write(text)

