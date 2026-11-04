import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/cashgo_api.dart';
import 'screens/agents_map_screen.dart';
import 'screens/login_screen.dart';
import 'screens/send_money_screen.dart';
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
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: context.watch<AuthState>().isLoggedIn
          ? const _Home()
          : const LoginScreen(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('CashGo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('KYC: ${auth.kycStatus ?? "unknown"}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Money'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.map),
              label: const Text('Find Pickup Agents'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AgentsMapScreen(destCountry: 'NG'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
