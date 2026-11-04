import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/cashgo_api.dart';
import 'screens/agents_map_screen.dart';
import 'screens/send_money_screen.dart';
import 'state/send_state.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => CashGoApi()),
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

  // Demo sender id from scripts/seed.py — replace with real auth session.
  static const demoSenderId = String.fromEnvironment('SENDER_ID',
      defaultValue: '00000000-0000-0000-0000-000000000000');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CashGo',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CashGo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Money'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const SendMoneyScreen(senderId: CashGoApp.demoSenderId),
                ),
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
