import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  String dbPath = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db';
  print('Opening database at $dbPath');
  
  var db = await databaseFactory.openDatabase(dbPath);
  
  var results = await db.rawQuery("SELECT name, sql FROM sqlite_master WHERE type='table' AND sql LIKE '%work_orders_old%'");
  if (results.isEmpty) {
    print('No broken tables found.');
  } else {
    print('Found broken tables:');
    for (var row in results) {
      print(' - ${row['name']}');
    }
    
    await db.execute('PRAGMA writable_schema = ON;');
    await db.execute("UPDATE sqlite_master SET sql = replace(sql, 'work_orders_old', 'work_orders') WHERE type='table' AND sql LIKE '%work_orders_old%'");
    await db.execute('PRAGMA writable_schema = OFF;');
    
    // Increment schema_version to force reload
    var versionRow = await db.rawQuery('PRAGMA schema_version;');
    var version = versionRow.first.values.first as int;
    await db.execute('PRAGMA schema_version = ${version + 1};');
    
    print('Repaired schema successfully.');
  }
  
  await db.close();
  print('Done.');
  exit(0);
}
