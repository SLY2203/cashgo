import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin REST client for the CashGo FastAPI backend.
class CashGoApi {
  CashGoApi({this.baseUrl = 'http://10.0.2.2:8000/api/v1'});
  final String baseUrl;

  Future<Map<String, dynamic>> getQuote({
    required String sourceCountry,
    required String destCountry,
    required String sendCurrency,
    required String payoutCurrency,
    required double sendAmount,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/remittances/quote/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'source_country': sourceCountry,
        'dest_country': destCountry,
        'send_currency': sendCurrency,
        'payout_currency': payoutCurrency,
        'send_amount': sendAmount,
      }),
    );
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, res.body);
    }
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> createTransfer({
    required String quoteId,
    required String senderId,
    required String recipientPhone,
    required String recipientFullName,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/remittances/transfer/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'quote_id': quoteId,
        'sender_id': senderId,
        'recipient_phone': recipientPhone,
        'recipient_full_name': recipientFullName,
        'payout_method': 'CASH_PICKUP',
      }),
    );
    if (res.statusCode != 201) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body);
  }

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
    final res = await http.get(uri);
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
