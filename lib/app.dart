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
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/ui_scale_provider.dart';
import 'core/widgets/window_title_bar.dart';

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
        textTheme: ShadTextTheme.fromGoogleFont(GoogleFonts.prompt),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadSlateColorScheme.dark(),
        textTheme: ShadTextTheme.fromGoogleFont(GoogleFonts.prompt),
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
                    size: Size(logicalWidth, logicalHeight - 38 / scale), // Adjust for title bar
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Column(
                    children: [
                      const WindowTitleBar(),
                      Expanded(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxWidth: logicalWidth,
                          maxHeight: logicalHeight - 38 / scale,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: child,
                          ),
                        ),
                      ),
                    ],
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset(
            'assets/images/splash.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(),
          ),
          
          // Loading Indicator overlay at the bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36, height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.0,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('กำลังเชื่อมต่อฐานข้อมูล...',
                      style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
