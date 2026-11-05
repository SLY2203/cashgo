import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/cashgo_api.dart';
import '../state/auth_state.dart';
import 'agents_map_screen.dart';
import 'scan_screen.dart';
import 'send_money_screen.dart';
import 'voucher_screen.dart';

/// Dashboard: wallet balances + transaction history with live statuses.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _wallets = [];
  List<dynamic> _txns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final api = context.read<CashGoApi>();
    try {
      final w = await api.wallets();
      final t = await api.transactions();
      setState(() {
        _wallets = w;
        _txns = t;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('CashGo'),
        actions: [
          if (auth.kycStatus != 'VERIFIED')
            TextButton.icon(
              onPressed: () => showDialog(
                  context: context, builder: (_) => const KycDialog()),
              icon: const Icon(Icons.verified_user, color: Colors.white),
              label: const Text('Verify KYC',
                  style: TextStyle(color: Colors.white)),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan agent QR',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScanScreen()),
            ).then((didScan) { if (didScan == true) _refresh(); }),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Pickup agents',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AgentsMapScreen(destCountry: 'ZA')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SendMoneyScreen()),
        ).then((_) => _refresh()),
        icon: const Icon(Icons.send),
        label: const Text('Send'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(
                wallets: _wallets,
                loading: _loading,
                onTopup: _refresh),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Transactions',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_loading) const SizedBox(
                    height: 16, width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 8),
            if (!_loading && _txns.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                    child: Text('No transfers yet — send your first one!')),
              ),
            for (final t in _txns) _TxnTile(txn: t),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final List<dynamic> wallets;
  final bool loading;
  final VoidCallback onTopup;
  const _BalanceCard({required this.wallets, required this.loading,
                      required this.onTopup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF15803d), Color(0xFF22c55e)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wallet balance',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          if (wallets.isEmpty)
            Text(loading ? 'Loading…' : '\$0.00 USD',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold))
          else
            for (final w in wallets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${double.parse(w['balance'].toString()).toStringAsFixed(2)} ${w['currency']}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold),
                    ),
                    if (double.parse(w['escrowed'].toString()) > 0)
                      Text(
                        '${double.parse(w['escrowed'].toString()).toStringAsFixed(2)} in escrow',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54)),
              icon: const Icon(Icons.add_card),
              label: const Text('Add funds'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => TopupDialog(onDone: onTopup),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dev top-up dialog — swap for Paystack/Flutterwave card capture in prod.
class TopupDialog extends StatefulWidget {
  final VoidCallback onDone;
  const TopupDialog({super.key, required this.onDone});

  @override
  State<TopupDialog> createState() => _TopupDialogState();
}

class _TopupDialogState extends State<TopupDialog> {
  final _amount = TextEditingController();
  String _ccy = 'USD';
  bool _busy = false;
  String? _error;
  String? _pendingRef;

  static const _ccys = ['USD', 'GBP', 'ZMW', 'TZS', 'ZAR', 'ZWG'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add funds'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _ccy,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: _ccys
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _ccy = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_pendingRef != null)
          FilledButton(
            onPressed: () async {
              final s = await context
                  .read<CashGoApi>()
                  .paymentStatus(_pendingRef!);
              if (s['status'] == 'PAID') {
                widget.onDone();
                if (context.mounted) Navigator.pop(context);
              } else {
                setState(() => _error = 'Payment not confirmed yet');
              }
            },
            child: const Text("I've paid"),
          )
        else
          FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  final amt = double.tryParse(_amount.text) ?? 0;
                  if (amt <= 0) {
                    setState(() => _error = 'Enter an amount');
                    return;
                  }
                  setState(() => _busy = true);
                  try {
                    final res = await context
                        .read<CashGoApi>()
                        .topup(_ccy, amt);
                    if (res['payment_url'] != null) {
                      // Paystack hosted checkout — pay in browser, webhook credits
                      await launchUrl(Uri.parse(res['payment_url']),
                          mode: LaunchMode.externalApplication);
                      setState(() {
                        _busy = false;
                        _error = 'Complete payment in browser — '
                            'balance updates automatically';
                        _pendingRef = res['reference'];
                      });
                    } else {
                      widget.onDone();
                      if (context.mounted) Navigator.pop(context);
                    }
                  } on ApiException catch (e) {
                    setState(() {
                      _busy = false;
                      _error = e.toString();
                    });
                  }
                },
          child: const Text('Top up'),
        ),
      ],
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TxnTile({required this.txn});

  static const _statusStyle = {
    'PENDING': (Color(0xFFe0e7ff), Color(0xFF3730a3), 'Processing'),
    'READY_FOR_PICKUP': (Color(0xFFfef3c7), Color(0xFF92400e), 'Ready for pickup'),
    'COMPLETED': (Color(0xFFd1fae5), Color(0xFF065f46), 'Withdrawn'),
    'CANCELLED': (Color(0xFFfee2e2), Color(0xFF991b1b), 'Cancelled'),
    'FAILED': (Color(0xFFfee2e2), Color(0xFF991b1b), 'Failed'),
    'EXPIRED': (Color(0xFFf3f4f6), Color(0xFF4b5563), 'Expired'),
  };

  @override
  Widget build(BuildContext context) {
    final status = txn['status'] as String;
    final (bg, fg, label) =
        _statusStyle[status] ?? (Colors.grey.shade200, Colors.grey.shade800, status);
    final date = DateTime.parse(txn['created_at']).toLocal();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VoucherScreen(transaction: txn)),
        ),
        leading: CircleAvatar(
          backgroundColor: bg,
          child: Icon(
            status == 'COMPLETED'
                ? Icons.check_circle
                : status == 'READY_FOR_PICKUP'
                    ? Icons.schedule
                    : Icons.receipt_long,
            color: fg, size: 20,
          ),
        ),
        title: Text(
          '${txn['payout_amount']} ${txn['payout_currency']} → ${txn['recipient_name']}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${txn['voucher_code']} · ${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(label,
              style: TextStyle(
                  color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// KYC dialog — exported for reuse by home + login flows.
class KycDialog extends StatefulWidget {
  const KycDialog({super.key});

  @override
  State<KycDialog> createState() => _KycDialogState();
}

class _KycDialogState extends State<KycDialog> {
  final _id = TextEditingController();
  String _doc = 'NATIONAL_ID';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Identity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _doc,
            decoration: const InputDecoration(labelText: 'Document type'),
            items: const [
              DropdownMenuItem(value: 'NATIONAL_ID', child: Text('National ID')),
              DropdownMenuItem(value: 'PASSPORT', child: Text('Passport')),
              DropdownMenuItem(
                  value: 'DRIVERS_LICENSE', child: Text("Driver's license")),
            ],
            onChanged: (v) => setState(() => _doc = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'ID number'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await context
                      .read<AuthState>()
                      .submitKyc(_doc, _id.text.trim());
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
