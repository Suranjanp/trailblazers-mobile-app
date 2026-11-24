
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AppSettings.instance.load();

  runApp(const TrailblazerApp());
}

class TrailblazerApp extends StatelessWidget {
  const TrailblazerApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    const orange = Color(0xFFF15A24);
    const navy = Color(0xFF00335C);

    final scheme = ColorScheme.fromSeed(
      seedColor: orange,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFFFF8A55) : orange,
      onPrimary: isDark ? const Color(0xFF25130D) : Colors.white,
      secondary: isDark
          ? const Color(0xFF83C9E8)
          : const Color(0xFF005E85),
      onSecondary: isDark
          ? const Color(0xFF082332)
          : Colors.white,
      surface: isDark
          ? const Color(0xFF182431)
          : Colors.white,
      onSurface: isDark
          ? const Color(0xFFF2F5F8)
          : const Color(0xFF172B3A),
      surfaceContainerLowest: isDark
          ? const Color(0xFF101A24)
          : Colors.white,
      surfaceContainerLow: isDark
          ? const Color(0xFF1D2B39)
          : const Color(0xFFF7F8FA),
      surfaceContainer: isDark
          ? const Color(0xFF243443)
          : const Color(0xFFF0F3F6),
      surfaceContainerHigh: isDark
          ? const Color(0xFF2B3D4D)
          : const Color(0xFFE8EDF1),
      surfaceContainerHighest: isDark
          ? const Color(0xFF34495A)
          : const Color(0xFFDDE5EB),
      onSurfaceVariant: isDark
          ? const Color(0xFFBBC8D3)
          : const Color(0xFF526575),
      outline: isDark
          ? const Color(0xFF607383)
          : const Color(0xFF8797A4),
      error: isDark
          ? const Color(0xFFFF8A80)
          : const Color(0xFFB3261E),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF101A24)
          : const Color(0xFFF7F8FA),
      canvasColor: scheme.surface,

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.35),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navy,
        indicatorColor: const Color(0xFF005E85),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? orange
                : Colors.white,
          ),
        ),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: Colors.white),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        textStyle: TextStyle(color: scheme.onSurface),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, child) {
        return MaterialApp(
          title: 'Trailblazer',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: AppSettings.instance.themeMode,
          home: const AuthScreen(),
          routes: {
            '/signup': (_) => const AuthScreen(signUp: true),
            '/home': (_) => const MainScreen(),
          },
        );
      },
    );
  }
}
