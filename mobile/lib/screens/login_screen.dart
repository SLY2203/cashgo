import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_state.dart';

/// Register-or-login via phone OTP. New users get a name+country form;
/// existing users go straight to OTP.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: '+234');
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _registering = false;
  bool _otpSent = false;
  String _country = 'NG';

  static const _countries = {'NG': 'Nigeria', 'GH': 'Ghana', 'KE': 'Kenya', 'US': 'USA'};

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(title: const Text('CashGo')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.send, size: 64, color: Colors.green),
          const SizedBox(height: 24),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Phone (E.164)', prefixText: ''),
          ),
          if (_registering) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _country,
              decoration: const InputDecoration(labelText: 'Country'),
              items: _countries.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _country = v!),
            ),
          ],
          if (_otpSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6-digit code'),
            ),
            if (auth.devCode != null)
              Text('Dev code: ${auth.devCode}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          if (auth.busy) const Center(child: CircularProgressIndicator()),
          if (auth.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(auth.error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: auth.busy ? null : () => _submit(context),
            child: Text(_otpSent
                ? 'Verify & sign in'
                : _registering
                    ? 'Create account'
                    : 'Send code'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _registering = !_registering;
              _otpSent = false;
            }),
            child: Text(_registering
                ? 'Already have an account? Sign in'
                : 'New here? Create account'),
          ),
        ],
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
      return; // register returns a JWT immediately
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
