import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../api/cashgo_api.dart';

/// Scans an agent's QR: {"op":"cashin"|"cashout","agent_id","amount","currency"}
/// cashin  → credits wallet instantly
/// cashout → claims a matching incoming READY_FOR_PICKUP transfer
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _handled = false;
  String? _result;
  bool _error = false;

  Future<void> _onDetect(String raw) async {
    if (_handled) return;
    _handled = true;
    try {
      final p = jsonDecode(raw) as Map<String, dynamic>;
      final api = context.read<CashGoApi>();
      final Map<String, dynamic> res = p['op'] == 'cashin'
          ? await api.scanCashin(p['agent_id'], (p['amount'] as num).toDouble(),
              p['currency'])
          : await api.scanCashout(p['agent_id'],
              (p['amount'] as num).toDouble(), p['currency']);
      setState(() {
        _result = p['op'] == 'cashin'
            ? 'Credited ${res['credited']} ${res['currency']} at '
                '${res['agent']}\nRef: ${res['reference']}\n'
                'Balance: ${res['new_balance']} ${res['currency']}'
            : 'Collected ${res['amount']} at ${res['agent']}';
      });
    } catch (e) {
      setState(() {
        _error = true;
        _result = 'Not a valid CashGo QR or transfer not found';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Agent QR')),
      body: _result != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_error ? Icons.error : Icons.check_circle,
                        size: 64, color: _error ? Colors.red : Colors.green),
                    const SizedBox(height: 16),
                    Text(_result!, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, !_error),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            )
          : MobileScanner(
              onDetect: (capture) {
                for (final b in capture.barcodes) {
                  if (b.rawValue != null) {
                    _onDetect(b.rawValue!);
                    break;
                  }
                }
              },
            ),
    );
  }
}
