import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090B10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RenPlayApp());
}

class RenPlayApp extends StatelessWidget {
  const RenPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bgCanvas = Color(0xFF090B10);
    const bgSurface = Color(0xFF11151F);
    const bgElevated = Color(0xFF171C29);
    const borderSubtle = Color(0xFF232A3B);
    const accentPrimary = Color(0xFF3B82F6);

    final darkScheme = ColorScheme.fromSeed(
      seedColor: accentPrimary,
      brightness: Brightness.dark,
      primary: accentPrimary,
      secondary: const Color(0xFF06B6D4),
      surface: bgSurface,
    );

    return MaterialApp(
      title: 'RenPlay Studio',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgCanvas,
        cardColor: bgSurface,
        colorScheme: darkScheme,
        dividerColor: borderSubtle,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgCanvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: bgSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: borderSubtle),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: bgElevated,
          contentTextStyle: const TextStyle(
            color: Color(0xFFF3F6FC),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: borderSubtle),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const LibraryScreen(),
    );
  }
}
