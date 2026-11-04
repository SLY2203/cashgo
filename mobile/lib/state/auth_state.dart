import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/cashgo_api.dart';

/// Phone + OTP auth. Persists the JWT + user id across launches.
class AuthState extends ChangeNotifier {
  AuthState(this.api);

  final CashGoApi api;
  static const _kToken = 'jwt';
  static const _kUserId = 'user_id';

  String? userId;
  String? kycStatus;
  bool get isLoggedIn => userId != null;

  bool busy = false;
  String? error;
  String? devCode; // OTP simulator echo — hidden in prod

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kToken);
    userId = prefs.getString(_kUserId);
    if (token != null && userId != null) api.token = token;
    notifyListeners();
  }

  Future<void> _saveSession(Map<String, dynamic> res) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, res['access_token']);
    await prefs.setString(_kUserId, res['user_id']);
    api.token = res['access_token'];
    userId = res['user_id'];
    kycStatus = res['kyc_status'];
  }

  Future<bool> register({
    required String phone,
    required String fullName,
    required String countryCode,
  }) => _run(() async {
        await _saveSession(await api.register(
            phone: phone, fullName: fullName, countryCode: countryCode));
      });

  Future<bool> requestOtp(String phone) => _run(() async {
        devCode = await api.requestOtp(phone);
      });

  Future<bool> verifyOtp(String phone, String code) => _run(() async {
        await _saveSession(await api.verifyOtp(phone, code));
        devCode = null;
      });

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    api.token = null;
    userId = null;
    kycStatus = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      busy = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.toString();
    } catch (_) {
      error = 'Network error — the server may be waking up, try again';
    }
    busy = false;
    notifyListeners();
    return false;
  }
}
