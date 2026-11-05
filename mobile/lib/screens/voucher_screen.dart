import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Digital receipt: voucher code + QR + real status timeline with timestamps.
class VoucherScreen extends StatelessWidget {
  final Map<String, dynamic> transaction;
  const VoucherScreen({super.key, required this.transaction});

  static const _statusLabels = {
    'PENDING': 'Transfer created',
    'READY_FOR_PICKUP': 'Ready for cash pickup',
    'COMPLETED': 'Recipient withdrew cash',
    'CANCELLED': 'Cancelled — funds returned',
    'FAILED': 'Failed',
    'EXPIRED': 'Expired',
  };

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final status = t['status'] as String;
    final history = (t['status_history'] as List?) ?? [];
    final paidOut = t['paid_out_at'] != null
        ? DateTime.parse(t['paid_out_at']).toLocal()
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            status == 'COMPLETED' ? Icons.check_circle
                : status == 'CANCELLED' || status == 'FAILED'
                    ? Icons.cancel
                    : Icons.schedule,
            color: status == 'COMPLETED' ? Colors.green
                : status == 'CANCELLED' || status == 'FAILED'
                    ? Colors.red
                    : Colors.orange,
            size: 56,
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${t['payout_amount']} ${t['payout_currency']}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Center(child: Text('for ${t['recipient_name']}')),
          if (paidOut != null)
            Center(
              child: Text(
                'Withdrawn ${_fmt(paidOut)}',
                style: const TextStyle(color: Colors.green),
              ),
            ),
          const SizedBox(height: 24),
          if (status != 'COMPLETED' && status != 'CANCELLED')
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
          const Text('Timeline',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._timeline(history, status),
        ],
      ),
    );
  }

  List<Widget> _timeline(List<dynamic> history, String status) {
    final tiles = <Widget>[];
    for (var i = 0; i < history.length; i++) {
      final h = history[i];
      final s = h['status'] as String;
      final at = DateTime.tryParse(h['at'] ?? '')?.toLocal();
      tiles.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_statusLabels[s] ?? s}',
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          if (at != null)
            Text(_fmt(at),
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ));
      tiles.add(const SizedBox(height: 10));
    }
    if (status == 'READY_FOR_PICKUP' || status == 'PENDING') {
      tiles.add(Row(children: const [
        Icon(Icons.radio_button_unchecked, size: 18, color: Colors.grey),
        SizedBox(width: 8),
        Text('Awaiting recipient pickup',
            style: TextStyle(color: Colors.grey)),
      ]));
    }
    return tiles;
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value)],
        ),
      );
}
