import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('Initializing IoT API Gateway...');
  
  // Initialize FFI for Windows/Desktop
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  // Database Path (Network Shared DB)
  final dbPath = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db';
  
  var db;
  try {
    db = await databaseFactory.openDatabase(dbPath);
    print('Connected to database at: \');
  } catch (e) {
    print('Failed to connect to database: \');
    exit(1);
  }

  // Start HTTP Server on port 8080
  final port = 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('===================================================');
  print('IoT API Gateway is listening on port \');
  print('Ready to receive machine running hours.');
  print('===================================================');
  print('Endpoint: POST http://localhost:\/api/update_hours');
  print('Payload Example: {"machine_no": "AP-06", "hours": 1500.5}');
  print('===================================================');

  await for (HttpRequest request in server) {
    // Add CORS headers so it can be called from anywhere
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      continue;
    }

    if (request.method == 'POST' && request.uri.path == '/api/update_hours') {
      try {
        final content = await utf8.decoder.bind(request).join();
        final data = jsonDecode(content);
        
        final machineNo = data['machine_no'];
        final hours = data['hours'];
        
        if (machineNo == null || hours == null) {
          request.response.statusCode = 400;
          request.response.write(jsonEncode({'error': 'Missing machine_no or hours'}));
          await request.response.close();
          continue;
        }

        // Find machine_id by machine_no
        final machineResult = await db.query(
          'machines', 
          columns: ['machine_id'], 
          where: 'machine_no = ?', 
          whereArgs: [machineNo]
        );
        
        if (machineResult.isEmpty) {
          print('[\] Not Found: Machine \');
          request.response.statusCode = 404;
          request.response.write(jsonEncode({'error': 'Machine not found'}));
        } else {
          final machineId = machineResult.first['machine_id'];
          final uuid = 'IOT-' + DateTime.now().millisecondsSinceEpoch.toString();
          
          // Insert into running hours table
          await db.insert('machine_running_hours', {
            'hours_id': uuid,
            'machine_id': machineId,
            'cumulative_hours': hours,
            'recorded_date': DateTime.now().toIso8601String(),
            'recorded_by': 'SYSTEM_IOT' // Indicates it was updated by API
          });
          
          print('[\] SUCCESS: Updated \ to \ Hrs');
          request.response.statusCode = 200;
          request.response.write(jsonEncode({'success': true, 'message': 'Running hours updated successfully'}));
        }
      } catch (e) {
        print('[\] ERROR: \');
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': e.toString()}));
      }
    } else {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'Endpoint Not Found. Use POST /api/update_hours'}));
    }
    await request.response.close();
  }
}
