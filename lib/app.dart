import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/config/app_config.dart';
import 'core/database/db_connection.dart';
import 'core/database/db_status_provider.dart';
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
        await DbConnection.instance.connect(
          config,
          skipInitialization: DbConnection.isNetworkPath(config.dbPath),
        );
        ref.read(dbStatusProvider.notifier).setConnected(config.dbPath);
      } catch (e) {
        ref.read(dbStatusProvider.notifier).setError(config.dbPath, e);
        debugPrint('Startup DB connect failed for ${config.dbPath}: $e');
      }
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
          child: Builder(
            builder: (context) => CircularThemeRevealOverlay(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Determine logical size to fill the window at the given scale
                  final logicalWidth = constraints.maxWidth / scale;
                  final logicalHeight = constraints.maxHeight / scale;

                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(
                        logicalWidth,
                        logicalHeight - 38 / scale,
                      ), // Adjust for title bar
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
      backgroundColor: const Color(0xFF0C0E14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset(
            'assets/images/splash.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(),
          ),

          // Subtle gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // Loading Indicator overlay at the bottom
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.0,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'กำลังเชื่อมต่อฐานข้อมูล...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFF1F5F9),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
