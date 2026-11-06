import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/cashgo_api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/auth_state.dart';
import 'state/send_state.dart';

/// CashGo design tokens.
class Cg {
  static const primary = Color(0xFF0F766E);
  static const primaryDark = Color(0xFF115E59);
  static const accent = Color(0xFF14B8A6);
  static const bg = Color(0xFFF4F7F6);
  static const ink = Color(0xFF0F172A);
  static const inkSoft = Color(0xFF64748B);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
}

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => CashGoApi()),
        ChangeNotifierProvider(
          create: (ctx) => AuthState(ctx.read<CashGoApi>())..restore(),
        ),
        ChangeNotifierProvider(
          create: (ctx) => SendState(ctx.read<CashGoApi>()),
        ),
      ],
      child: const CashGoApp(),
    ),
  );
}

class CashGoApp extends StatelessWidget {
  const CashGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true);
    return MaterialApp(
      title: 'CashGo',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Cg.primary,
          primary: Cg.primary,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Cg.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Cg.bg,
          foregroundColor: Cg.ink,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: Cg.ink, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE6EBEA))),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD9E2E0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD9E2E0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Cg.primary, width: 1.6)),
          labelStyle: const TextStyle(color: Cg.inkSoft),
          floatingLabelStyle: const TextStyle(color: Cg.primary),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Cg.primary,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Cg.primary,
            minimumSize: const Size(0, 46),
            side: const BorderSide(color: Cg.primary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        listTileTheme: const ListTileThemeData(
            contentPadding: EdgeInsets.symmetric(horizontal: 16)),
        snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating),
      ),
      home: context.watch<AuthState>().isLoggedIn
          ? const HomeScreen()
          : const LoginScreen(),
    );
  }
}
