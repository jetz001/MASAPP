import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/config/app_config.dart';
import 'core/database/db_connection.dart';
import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'package:circular_theme_reveal/circular_theme_reveal.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'core/theme/ui_scale_provider.dart';

class MasApp extends ConsumerStatefulWidget {
  const MasApp({super.key});

  @override
  ConsumerState<MasApp> createState() => _MasAppState();
}

class _MasAppState extends ConsumerState<MasApp> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final config = await AppConfigService.load();
    if (config != null) {
      try {
        await DbConnection.instance.connect(config);
      } catch (_) {}
    }
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        theme: AppTheme.dark,
        home: const _SplashScreen(),
        debugShowCheckedModeBanner: false,
      );
    }

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return ShadApp.router(
      title: 'MASAPP',
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.light(),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadSlateColorScheme.dark(),
      ),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      materialThemeBuilder: (context, theme) => 
          themeMode == ThemeMode.light ? AppTheme.light : AppTheme.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        
        final scale = ref.watch(uiScaleProvider);
        
        return ScaffoldMessenger(
          child: CircularThemeRevealOverlay(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Determine logical size to fill the window at the given scale
                final logicalWidth = constraints.maxWidth / scale;
                final logicalHeight = constraints.maxHeight / scale;
                
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(logicalWidth, logicalHeight),
                    // We also scale the textFactor to handle complex widgets 
                    // that might ignore custom sizes but respect text scaling
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: logicalWidth,
                    maxHeight: logicalHeight,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topLeft,
                      child: child,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.precision_manufacturing_rounded,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            const Text('MASAPP',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white,
                )),
            const SizedBox(height: 8),
            const Text('Maintenance Super App',
                style: TextStyle(fontSize: 14, color: Colors.white38)),
            const SizedBox(height: 32),
            const SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 12),
            const Text('กำลังเชื่อมต่อฐานข้อมูล...',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}
