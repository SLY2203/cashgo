import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/cashgo_api.dart';
import '../state/send_state.dart';
import 'voucher_screen.dart';

/// Send Money — pickers are driven by live /corridors/ data, so admin-added
/// corridors & payout currencies appear without an app update.
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  static const _countryNames = {
    'US': 'USA', 'GB': 'UK', 'ZM': 'Zambia', 'TZ': 'Tanzania',
    'ZA': 'South Africa', 'ZW': 'Zimbabwe', 'NG': 'Nigeria',
    'KE': 'Kenya', 'GH': 'Ghana',
  };

  List<dynamic> _corridors = [];
  String? _loadError;

  // selected corridor tuple (src, sendCcy, dst) + chosen payout ccy
  (String, String, String)? _corridor;
  String? _payoutCcy;

  @override
  void initState() {
    super.initState();
    _loadCorridors();
  }

  Future<void> _loadCorridors() async {
    try {
      final c = await context.read<CashGoApi>().corridors();
      setState(() => _corridors = c);
      if (c.isNotEmpty) _select(c.first);
    } on ApiException catch (e) {
      setState(() => _loadError = e.toString());
    }
  }

  void _select(Map<String, dynamic> c, [String? payout]) {
    setState(() {
      _corridor = (c['source_country'], c['send_currency'], c['dest_country']);
      _payoutCcy = payout ?? (c['payout_currencies'] as List).first;
    });
    context.read<SendState>().update(
          sourceCountry: _corridor!.$1,
          sendCurrency: _corridor!.$2,
          destCountry: _corridor!.$3,
          payoutCurrency: _payoutCcy,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SendState>();
    final q = state.quote;

    // corridors matching the selected source
    final srcKey = _corridor == null ? null : (_corridor!.$1, _corridor!.$2);
    (String, String, String) keyOf(Map c) => (
        c['source_country'] as String,
        c['send_currency'] as String,
        c['dest_country'] as String);
    final dests = <(String, String, String), Map>{
      for (final c in _corridors.cast<Map>())
        if ((keyOf(c).$1, keyOf(c).$2) == srcKey) keyOf(c): c
    };
    final sources = <(String, String)>{
      for (final c in _corridors.cast<Map>()) (keyOf(c).$1, keyOf(c).$2)
    };
    final payouts = _corridor == null
        ? <String>[]
        : List<String>.from(
            dests[_corridor]?['payout_currencies'] as List? ?? []);

    return Scaffold(
      appBar: AppBar(title: const Text('Send Money')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadError != null)
            Text(_loadError!, style: const TextStyle(color: Colors.red)),
          // --- send from (country + currency) ----------------------------------
          DropdownButtonFormField<(String, String)>(
            value: srcKey,
            decoration:
                const InputDecoration(labelText: 'Sending from'),
            items: sources
                .map((k) => DropdownMenuItem<(String, String)>(
                    value: k,
                    child: Text(
                        '${_countryNames[k.$1] ?? k.$1} (${k.$2})')))
                .toList(),
            onChanged: (k) {
              if (k == null) return;
              final first = _corridors.firstWhere((c) =>
                  (c['source_country'], c['send_currency']) == k);
              _select(Map<String, dynamic>.from(first));
            },
          ),
          const SizedBox(height: 12),
          // --- destination -------------------------------------------------------
          DropdownButtonFormField<String>(
            value: _corridor?.$3,
            decoration: const InputDecoration(labelText: 'Destination'),
            items: dests.keys
                .map((k) => DropdownMenuItem<String>(
                    value: k.$3,
                    child: Text(_countryNames[k.$3] ?? k.$3)))
                .toList(),
            onChanged: (dst) {
              if (dst == null) return;
              final c = dests.entries
                  .firstWhere((e) => e.key.$3 == dst)
                  .value;
              _select(Map<String, dynamic>.from(c));
            },
          ),
          const SizedBox(height: 12),
          // --- payout currency (receiver's choice) --------------------------------
          DropdownButtonFormField<String>(
            value: _payoutCcy,
            decoration:
                const InputDecoration(labelText: 'Receiver gets'),
            items: payouts
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              setState(() => _payoutCcy = v);
              context
                  .read<SendState>()
                  .update(payoutCurrency: v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'You send (${_corridor?.$2 ?? ""})',
              prefixIcon: const Icon(Icons.attach_money),
            ),
            onChanged: (v) => context
                .read<SendState>()
                .update(sendAmount: double.tryParse(v) ?? 0),
          ),
          const SizedBox(height: 16),
          if (state.loading)
            const Center(child: CircularProgressIndicator()),
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
                labelText: 'Recipient phone (E.164)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send now'),
            onPressed: q == null || state.loading
                ? null
                : () async {
                    final ok =
                        await context.read<SendState>().submitTransfer(
                              recipientPhone: _phoneCtrl.text.trim(),
                              recipientFullName: _nameCtrl.text.trim(),
                            );
                    if (ok && context.mounted) {
                      final txn =
                          context.read<SendState>().transaction!;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VoucherScreen(transaction: txn),
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
