import 'package:flutter/material.dart';
import 'screens/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RenPlayApp());
}

class RenPlayApp extends StatelessWidget {
  const RenPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenPlay Runner',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Gamer dark theme default
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121217),
        cardTheme: const CardTheme(
          color: Color(0xFF1E1E26),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
          background: const Color(0xFF121217),
          surface: const Color(0xFF1E1E26),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF181820),
          elevation: 0,
        ),
      ),
      home: const LibraryScreen(),
    );
  }
}
