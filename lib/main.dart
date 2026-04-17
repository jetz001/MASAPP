import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure desktop window
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(1024, 700),
    center: true,
    title: 'MASAPP — Maintenance Super App',
    backgroundColor: Color(0xFF0F1117),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  // Global error logging
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('GLOBAL ERROR: ${details.exception}');
  };

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    const ProviderScope(
      child: MasApp(),
    ),
  );
}
