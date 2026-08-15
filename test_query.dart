import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  var db = await databaseFactory.openDatabase(r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db', options: OpenDatabaseOptions(readOnly: true));
  
  var results = await db.rawQuery('''
    SELECT wo.wo_no, wo.title, wo.status, u.full_name as assigned_to, wo.machine_id, m.machine_no
    FROM work_orders wo
    LEFT JOIN users u ON u.user_id = wo.assigned_to
    LEFT JOIN machines m ON m.machine_id = wo.machine_id
    WHERE wo.status NOT IN ('completed', 'cancelled', 'rejected')
    ORDER BY wo.created_at DESC
  ''');
  
  print('---PENDING WORK ORDERS---');
  for (var row in results) {
    print('WO: ' + row['wo_no'].toString() + ', Status: ' + row['status'].toString() + ', Title: ' + row['title'].toString() + ', Machine: ' + row['machine_no'].toString() + ', Assigned: ' + row['assigned_to'].toString());
  }
  print('---END---');
  exit(0);
}
