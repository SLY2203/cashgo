import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Digital receipt: voucher code + QR + status timeline.
class VoucherScreen extends StatelessWidget {
  final Map<String, dynamic> transaction;
  const VoucherScreen({super.key, required this.transaction});

  static const _steps = [
    ('PENDING', 'Transfer created'),
    ('READY_FOR_PICKUP', 'Ready for pickup'),
    ('COMPLETED', 'Cash paid out'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final status = t['status'] as String;
    final currentStep =
        _steps.indexWhere((s) => s.$1 == status).clamp(0, _steps.length - 1);

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${t['payout_amount']} ${t['payout_currency']}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Center(child: Text('for ${t['recipient_name']}')),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Pickup voucher code'),
                  const SizedBox(height: 8),
                  Text(
                    t['voucher_code'],
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  const SizedBox(height: 12),
                  QrImageView(data: t['voucher_code'], size: 160),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _row('Sent', '${t['send_amount']} ${t['send_currency']}'),
          _row('Fee', '${t['fee_amount']} ${t['send_currency']}'),
          _row('Rate', t['exchange_rate'].toString()),
          _row('Recipient phone', t['recipient_phone']),
          const Divider(height: 32),
          const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < _steps.length; i++)
            Row(
              children: [
                Icon(
                  i <= currentStep
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: i <= currentStep ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_steps[i].$2} (${_steps[i].$1})',
                  style: TextStyle(
                    color: i <= currentStep ? Colors.black : Colors.grey,
                    fontWeight: i == currentStep
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value)],
        ),
      );
}
