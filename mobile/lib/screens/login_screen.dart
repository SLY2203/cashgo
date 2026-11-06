import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show Cg;
import '../state/auth_state.dart';

/// Register-or-login via phone OTP.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+263');
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _registering = false;
  bool _otpSent = false;
  String _country = 'ZW';

  static const _countries = {
    'ZW': 'Zimbabwe', 'ZA': 'South Africa',
    'ZM': 'Zambia', 'TZ': 'Tanzania',
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            // brand
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Cg.primary, Cg.accent],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Cg.primary.withOpacity(.35),
                    blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.north_east, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('CashGo',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800,
                    color: Cg.ink)),
            const Text('Move money across Africa, instantly.',
                style: TextStyle(color: Cg.inkSoft, fontSize: 14)),
            const SizedBox(height: 36),

            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone number', hintText: '+263 77 123 4567'),
            ),
            if (_registering) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _country,
                decoration: const InputDecoration(labelText: 'Country'),
                items: _countries.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _country = v!),
              ),
            ],
            if (_otpSent) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24,
                    fontWeight: FontWeight.w700, letterSpacing: 8),
                decoration: const InputDecoration(
                    labelText: 'Verification code', counterText: ''),
              ),
              if (auth.devCode != null)
                Center(
                  child: Text('Dev code: ${auth.devCode}',
                      style: const TextStyle(color: Cg.inkSoft, fontSize: 12)),
                ),
            ],
            const SizedBox(height: 24),
            if (auth.busy)
              const Center(
                  child: CircularProgressIndicator(color: Cg.primary)),
            if (auth.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(auth.error!,
                    style: const TextStyle(color: Cg.danger)),
              ),
            FilledButton(
              onPressed: auth.busy ? null : () => _submit(context),
              child: Text(_otpSent
                  ? 'Verify & sign in'
                  : _registering ? 'Create account' : 'Send code'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _registering = !_registering;
                _otpSent = false;
              }),
              child: Text(_registering
                  ? 'Already have an account? Sign in'
                  : 'New here? Create account',
                  style: const TextStyle(color: Cg.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final auth = context.read<AuthState>();
    if (_registering) {
      await auth.register(
          phone: _phone.text.trim(),
          fullName: _name.text.trim(),
          countryCode: _country);
      return;
    }
    if (!_otpSent) {
      if (await auth.requestOtp(_phone.text.trim())) {
        setState(() => _otpSent = true);
      }
    } else {
      await auth.verifyOtp(_phone.text.trim(), _code.text.trim());
    }
  }
}
