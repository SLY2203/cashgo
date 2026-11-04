import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/send_state.dart';
import 'voucher_screen.dart';

class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  static const corridors = {
    'US → Nigeria': ('US', 'NG', 'USD', 'NGN'),
    'US → Ghana': ('US', 'GH', 'USD', 'GHS'),
    'US → Kenya': ('US', 'KE', 'USD', 'KES'),
    'UK → Nigeria': ('GB', 'NG', 'GBP', 'NGN'),
  };
  String _corridor = corridors.keys.first;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SendState>();
    final q = state.quote;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Money')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _corridor,
            decoration: const InputDecoration(labelText: 'Corridor'),
            items: corridors.keys
                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
            onChanged: (k) {
              final c = corridors[k]!;
              setState(() => _corridor = k!);
              context.read<SendState>().update(
                    sourceCountry: c.$1,
                    destCountry: c.$2,
                    sendCurrency: c.$3,
                    payoutCurrency: c.$4,
                  );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'You send (${state.sendCurrency})',
              prefixIcon: const Icon(Icons.attach_money),
            ),
            onChanged: (v) => context
                .read<SendState>()
                .update(sendAmount: double.tryParse(v) ?? 0),
          ),
          const SizedBox(height: 16),
          if (state.loading) const Center(child: CircularProgressIndicator()),
          if (state.error != null)
            Text(state.error!, style: const TextStyle(color: Colors.red)),
          if (q != null) _QuoteCard(quote: q, state: state),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration:
                const InputDecoration(labelText: 'Recipient full name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Recipient phone (E.164, e.g. +234...)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send now'),
            onPressed: q == null || state.loading
                ? null
                : () async {
                    final ok = await context.read<SendState>().submitTransfer(
                          recipientPhone: _phoneCtrl.text.trim(),
                          recipientFullName: _nameCtrl.text.trim(),
                        );
                    if (ok && context.mounted) {
                      final txn =
                          context.read<SendState>().transaction!;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VoucherScreen(transaction: txn),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Map<String, dynamic> quote;
  final SendState state;
  const _QuoteCard({required this.quote, required this.state});

  @override
  Widget build(BuildContext context) {
    String money(dynamic v, String cur) =>
        '${double.parse(v.toString()).toStringAsFixed(2)} $cur';
    final expiry = DateTime.parse(quote['expires_at']);
    final secsLeft = expiry.difference(DateTime.now()).inSeconds;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Fee', money(quote['fee_amount'], quote['send_currency'])),
            _row('Total debit',
                money(quote['total_debit'], quote['send_currency'])),
            _row('Rate',
                '1 ${quote['send_currency']} = ${double.parse(quote['applied_rate'].toString()).toStringAsFixed(4)} ${quote['payout_currency']}'),
            const Divider(),
            _row('Recipient gets',
                money(quote['payout_amount'], quote['payout_currency']),
                bold: true),
            const SizedBox(height: 6),
            Text('Rate locked for ${secsLeft.clamp(0, 60)}s',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value,
                style:
                    TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          ],
        ),
      );
}
