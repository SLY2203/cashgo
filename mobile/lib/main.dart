import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/cashgo_api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/auth_state.dart';
import 'state/send_state.dart';

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
    return MaterialApp(
      title: 'CashGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF15803d),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF15803d),
          foregroundColor: Colors.white,
        ),
      ),
      home: context.watch<AuthState>().isLoggedIn
          ? const HomeScreen()
          : const LoginScreen(),
    );
  }
}
