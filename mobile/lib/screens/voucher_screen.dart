import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart' show Cg;

/// Digital receipt: status hero → ticket-style voucher → details → timeline.
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
    final done = status == 'COMPLETED';
    final failed = status == 'CANCELLED' || status == 'FAILED';

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // status hero
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE6EBEA)),
            ),
            child: Column(children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: (done ? Cg.success : failed ? Cg.danger : Cg.warning)
                      .withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  done ? Icons.check_rounded
                      : failed ? Icons.close_rounded
                      : Icons.schedule,
                  color: done ? Cg.success : failed ? Cg.danger : Cg.warning,
                  size: 34,
                ),
              ),
              const SizedBox(height: 12),
              Text('${t['payout_amount']} ${t['payout_currency']}',
                  style: const TextStyle(fontSize: 30,
                      fontWeight: FontWeight.w800, color: Cg.ink)),
              Text('to ${t['recipient_name']}',
                  style: const TextStyle(color: Cg.inkSoft)),
              if (paidOut != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Withdrawn ${_fmt(paidOut)}',
                      style: const TextStyle(color: Cg.success,
                          fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // voucher ticket (only while pickupable)
          if (!done && !failed)
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Cg.primaryDark, Cg.primary],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(22),
              child: Column(children: [
                const Text('PICKUP VOUCHER',
                    style: TextStyle(color: Colors.white70, fontSize: 11,
                        letterSpacing: 2, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(t['voucher_code'],
                    style: const TextStyle(color: Colors.white, fontSize: 30,
                        fontWeight: FontWeight.w800, letterSpacing: 3)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14)),
                  child: QrImageView(data: t['voucher_code'], size: 170),
                ),
                const SizedBox(height: 10),
                const Text('Show at any CashGo agent to collect',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            )
          else
            _DetailCard(children: [
              _row('Voucher', t['voucher_code']),
              _row('Sent', '${t['send_amount']} ${t['send_currency']}'),
              _row('Fee', '${t['fee_amount']} ${t['send_currency']}'),
              _row('Rate', t['exchange_rate'].toString()),
              _row('Recipient', t['recipient_phone']),
            ]),
          const SizedBox(height: 20),

          const Text('Timeline',
              style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 15, color: Cg.ink)),
          const SizedBox(height: 12),
          _Timeline(history: history, status: status, fmt: _fmt),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Cg.inkSoft)),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6EBEA))),
        child: Column(children: children),
      );
}

class _Timeline extends StatelessWidget {
  final List<dynamic> history;
  final String status;
  final String Function(DateTime) fmt;
  const _Timeline({required this.history, required this.status,
                   required this.fmt});

  static const _labels = VoucherScreen._statusLabels;

  @override
  Widget build(BuildContext context) {
    final steps = <Widget>[];
    for (var i = 0; i < history.length; i++) {
      final h = history[i];
      final s = h['status'] as String;
      final at = DateTime.tryParse(h['at'] ?? '')?.toLocal();
      steps.add(_Step(
        title: _labels[s] ?? s,
        when: at != null ? fmt(at) : '',
        done: true,
        last: i == history.length - 1 &&
            status != 'READY_FOR_PICKUP' && status != 'PENDING',
      ));
    }
    if (status == 'READY_FOR_PICKUP' || status == 'PENDING') {
      steps.add(const _Step(
          title: 'Awaiting recipient pickup', done: false, last: true));
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EBEA))),
      child: Column(children: steps),
    );
  }
}

class _Step extends StatelessWidget {
  final String title;
  final String when;
  final bool done;
  final bool last;
  const _Step({required this.title, this.when = '',
               required this.done, this.last = false});

  @override
  Widget build(BuildContext context) {
    final c = done ? Cg.success : Cg.inkSoft;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18, color: c),
            if (!last)
              Expanded(child: Container(width: 2, color: const Color(0xFFE6EBEA))),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(title,
                      style: TextStyle(color: c,
                          fontWeight: done ? FontWeight.w600 : null))),
                  if (when.isNotEmpty)
                    Text(when, style: const TextStyle(
                        color: Cg.inkSoft, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
