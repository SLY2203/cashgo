import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/cashgo_api.dart';
import '../main.dart' show Cg;
import '../state/auth_state.dart';
import 'agents_map_screen.dart';
import 'scan_screen.dart';
import 'send_money_screen.dart';
import 'voucher_screen.dart';

/// Dashboard: greeting → wallet hero → quick actions → transaction history.
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
      setState(() { _wallets = w; _txns = t; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.me == null) auth.loadMe();
    final first = (auth.me?['full_name'] ?? 'there')
        .toString().split(' ').first;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: Cg.primary,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // ---- header ------------------------------------------------
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hello, $first',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800,
                              color: Cg.ink)),
                      Text(
                        auth.kycStatus == 'VERIFIED'
                            ? 'Verified account'
                            : 'Complete identity verification',
                        style: const TextStyle(
                            color: Cg.inkSoft, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (auth.kycStatus != 'VERIFIED')
                  IconButton(
                    icon: const Icon(Icons.verified_user_outlined,
                        color: Cg.warning),
                    tooltip: 'Verify identity',
                    onPressed: () => showDialog(context: context,
                        builder: (_) => const KycDialog()),
                  ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Cg.inkSoft, size: 22),
                  onPressed: () => context.read<AuthState>().logout(),
                ),
              ]),
              const SizedBox(height: 16),

              _BalanceCard(wallets: _wallets, loading: _loading),
              const SizedBox(height: 20),

              // ---- quick actions -----------------------------------------
              Row(children: [
                _Action(icon: Icons.north_east, label: 'Send',
                    color: Cg.primary,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SendMoneyScreen()))
                        .then((_) => _refresh())),
                _Action(icon: Icons.add, label: 'Top up',
                    color: Cg.success,
                    onTap: () => showDialog(context: context,
                        builder: (_) => TopupDialog(onDone: _refresh))),
                _Action(icon: Icons.qr_code_scanner, label: 'Scan',
                    color: Cg.accent,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ScanScreen()))
                        .then((r) { if (r == true) _refresh(); })),
                _Action(icon: Icons.place_outlined, label: 'Agents',
                    color: Cg.warning,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) =>
                            const AgentsMapScreen(destCountry: 'ZA')))),
              ]),
              const SizedBox(height: 28),

              // ---- history ------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent activity',
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w700, color: Cg.ink)),
                  if (_loading) const SizedBox(height: 14, width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 10),
              if (!_loading && _txns.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE6EBEA))),
                  child: const Center(
                    child: Text('No transfers yet — send your first one',
                        style: TextStyle(color: Cg.inkSoft)),
                  ),
                ),
              for (final t in _txns) _TxnTile(txn: t),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- widgets --

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label,
                 required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600, color: Cg.ink)),
          ]),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final List<dynamic> wallets;
  final bool loading;
  const _BalanceCard({required this.wallets, required this.loading});

  @override
  Widget build(BuildContext context) {
    final hasEscrow = wallets.any(
        (w) => double.parse(w['escrowed'].toString()) > 0);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Cg.primaryDark, Cg.primary, Cg.accent],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Cg.primary.withOpacity(.3),
            blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              if (hasEscrow)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('Funds in escrow',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (wallets.isEmpty)
            Text(loading ? 'Loading…' : 'No wallets yet',
                style: const TextStyle(color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.bold))
          else
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                for (final w in wallets)
                  _WalletChip(wallet: w),
              ],
            ),
        ],
      ),
    );
  }
}

class _WalletChip extends StatelessWidget {
  final Map<String, dynamic> wallet;
  const _WalletChip({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final bal = double.parse(wallet['balance'].toString());
    final esc = double.parse(wallet['escrowed'].toString());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wallet['currency'],
              style: const TextStyle(color: Colors.white70, fontSize: 11,
                  fontWeight: FontWeight.w600, letterSpacing: .5)),
          Text(bal.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w800)),
          if (esc > 0)
            Text('${esc.toStringAsFixed(2)} escrowed',
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
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
    final (bg, fg, label) = _statusStyle[status] ??
        (Colors.grey.shade200, Colors.grey.shade800, status);
    final date = DateTime.parse(txn['created_at']).toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EBEA))),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VoucherScreen(transaction: txn)),
        ),
        leading: CircleAvatar(
          radius: 20, backgroundColor: bg,
          child: Icon(
            status == 'COMPLETED' ? Icons.check_circle
                : status == 'READY_FOR_PICKUP' ? Icons.schedule
                : Icons.north_east,
            color: fg, size: 18,
          ),
        ),
        title: Text(
          '${txn['payout_amount']} ${txn['payout_currency']} → ${txn['recipient_name']}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '${txn['voucher_code']} · ${date.day}/${date.month}/${date.year}',
          style: const TextStyle(fontSize: 12, color: Cg.inkSoft)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(label,
              style: TextStyle(color: fg, fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- dialogs (same)

/// Dev top-up dialog — Paystack hosted checkout when configured.
class TopupDialog extends StatefulWidget {
  final VoidCallback onDone;
  const TopupDialog({super.key, required this.onDone});

  @override
  State<TopupDialog> createState() => _TopupDialogState();
}

class _TopupDialogState extends State<TopupDialog> {
  final _amount = TextEditingController();
  String _ccy = 'ZAR';
  bool _busy = false;
  String? _error;
  String? _pendingRef;

  static const _ccys = ['ZAR', 'ZWG', 'ZMW', 'TZS', 'USD'];

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
                  style: const TextStyle(color: Cg.danger, fontSize: 12)),
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
            onPressed: _busy ? null : () async {
              final amt = double.tryParse(_amount.text) ?? 0;
              if (amt <= 0) {
                setState(() => _error = 'Enter an amount');
                return;
              }
              setState(() => _busy = true);
              try {
                final res = await context
                    .read<CashGoApi>().topup(_ccy, amt);
                if (res['payment_url'] != null) {
                  await launchUrl(Uri.parse(res['payment_url']),
                      mode: LaunchMode.externalApplication);
                  setState(() {
                    _busy = false;
                    _error = 'Complete payment in browser';
                    _pendingRef = res['reference'];
                  });
                } else {
                  widget.onDone();
                  if (context.mounted) Navigator.pop(context);
                }
              } on ApiException catch (e) {
                setState(() { _busy = false; _error = e.toString(); });
              }
            },
            child: const Text('Top up'),
          ),
      ],
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
          onPressed: _busy ? null : () async {
            setState(() => _busy = true);
            await context.read<AuthState>()
                .submitKyc(_doc, _id.text.trim());
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
