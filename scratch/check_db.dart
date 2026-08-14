import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:logger/logger.dart';

void main() async {
  final logger = Logger();
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;

  final userProfile = Platform.environment['USERPROFILE'] ?? '';
  final dbPath = p.join(userProfile, 'OneDrive', 'เอกสาร', 'masapp.db');

  if (!File(dbPath).existsSync()) {
    logger.i('Database not found at $dbPath');
    return;
  }

  var db = await databaseFactory.openDatabase(dbPath);
  var machines = await db.query(
    'machines',
    columns: ['machine_no', 'asset_no'],
  );

  logger.i('Existing Machines:');
  for (var m in machines) {
    logger.i('Machine No: ${m['machine_no']}, Asset No: ${m['asset_no']}');
  }

  await db.close();
}
