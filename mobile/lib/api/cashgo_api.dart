import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin REST client for the CashGo FastAPI backend.
/// Handles Bearer auth + retries for Render free-tier cold starts (~30s).
class CashGoApi {
  CashGoApi({this.baseUrl = 'https://cashgo-api.onrender.com/api/v1'});
  final String baseUrl;

  String? _token;
  set token(String? v) => _token = v;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// POST/GET with one automatic retry — free-tier services sleep and the
  /// first request can take up to ~30-40s.
  Future<http.Response> _request(
    Future<http.Response> Function() send, {
    int retries = 1,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await send().timeout(timeout);
      } on TimeoutException {
        if (attempt == retries) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw StateError('unreachable');
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) =>
      _request(() => http.post(Uri.parse('$baseUrl$path'),
          headers: _headers, body: jsonEncode(body)));

  Future<http.Response> _get(String path) =>
      _request(() => http.get(Uri.parse('$baseUrl$path'), headers: _headers));

  Map<String, dynamic> _json(http.Response res, {int? expect}) {
    if (expect != null && res.statusCode != expect) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  // ---- Auth -----------------------------------------------------------------
  Future<Map<String, dynamic>> register({
    required String phone,
    required String fullName,
    required String countryCode,
    String? email,
  }) async {
    final res = await _post('/auth/register/', {
      'phone': phone,
      'full_name': fullName,
      'country_code': countryCode,
      if (email != null) 'email': email,
    });
    return _json(res, expect: 201);
  }

  /// Returns the dev_code (OTP simulator) — in prod the code arrives by SMS.
  Future<String?> requestOtp(String phone) async {
    final res = await _post('/auth/otp/request/', {'phone': phone});
    return _json(res)['dev_code'] as String?;
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final res = await _post('/auth/otp/verify/', {'phone': phone, 'code': code});
    return _json(res);
  }

  Future<Map<String, dynamic>> submitKyc(
      String documentType, String idNumber) async {
    final res = await _post('/auth/kyc/',
        {'document_type': documentType, 'id_number': idNumber});
    if (res.statusCode != 200) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body);
  }

  // ---- Wallets ----------------------------------------------------------------
  Future<List<dynamic>> wallets() async {
    final res = await _get('/wallets/');
    if (res.statusCode != 200) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as List;
  }

  Future<Map<String, dynamic>> topup(String currency, double amount) async =>
      _json(await _post('/wallets/topup/', {'currency': currency, 'amount': amount}));

  // ---- Remittances --------------------------------------------------------------
  Future<List<dynamic>> corridors() async {
    final res = await _get('/remittances/corridors/');
    if (res.statusCode != 200) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as List;
  }


  Future<Map<String, dynamic>> getQuote({
    required String sourceCountry,
    required String destCountry,
    required String sendCurrency,
    required String payoutCurrency,
    required double sendAmount,
  }) async =>
      _json(await _post('/remittances/quote/', {
        'source_country': sourceCountry,
        'dest_country': destCountry,
        'send_currency': sendCurrency,
        'payout_currency': payoutCurrency,
        'send_amount': sendAmount,
      }), expect: 200);

  Future<Map<String, dynamic>> createTransfer({
    required String quoteId,
    required String recipientPhone,
    required String recipientFullName,
  }) async =>
      _json(await _post('/remittances/transfer/', {
        'quote_id': quoteId,
        'recipient_phone': recipientPhone,
        'recipient_full_name': recipientFullName,
        'payout_method': 'CASH_PICKUP',
      }), expect: 201);

  Future<List<dynamic>> transactions() async {
    final res = await _get('/remittances/transactions/');
    if (res.statusCode != 200) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as List;
  }

  // ---- Agents --------------------------------------------------------------------
  Future<List<dynamic>> nearestAgents({
    required double latitude,
    required double longitude,
    required String destCountry,
    int radiusMeters = 15000,
  }) async {
    final uri = Uri.parse('$baseUrl/agents/nearest/').replace(queryParameters: {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'radius_meters': '$radiusMeters',
      'dest_country': destCountry,
    });
    final res = await _request(() => http.get(uri, headers: _headers));
    if (res.statusCode != 200) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body);
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'HTTP $statusCode: $body';
}
