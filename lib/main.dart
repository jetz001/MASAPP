import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/ui_scale_provider.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-load scale settings to prevent debugger crash during build loop
  final prefs = await SharedPreferences.getInstance();
  final initialScale = prefs.getDouble('ui_scale_factor') ?? 1.0;

  // Configure desktop window
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 760),
    minimumSize: Size(1024, 680),
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
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(1024, 680));
  });

  runApp(
    ProviderScope(
      overrides: [
        uiScaleProvider.overrideWith(() => UiScaleNotifier(initialScale)),
      ],
      child: const MasApp(),
    ),
  );
}
