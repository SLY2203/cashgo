import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/cashgo_api.dart';

/// State for the Send Money flow: debounced quotes + transfer submission.
class SendState extends ChangeNotifier {
  SendState(this.api);

  final CashGoApi api;

  String sourceCountry = 'US';
  String destCountry = 'NG';
  String sendCurrency = 'USD';
  String payoutCurrency = 'NGN';
  double sendAmount = 0;

  Map<String, dynamic>? quote;
  Map<String, dynamic>? transaction;
  bool loading = false;
  String? error;
  Timer? _debounce;

  void update({
    String? sourceCountry,
    String? destCountry,
    String? sendCurrency,
    String? payoutCurrency,
    double? sendAmount,
  }) {
    this.sourceCountry = sourceCountry ?? this.sourceCountry;
    this.destCountry = destCountry ?? this.destCountry;
    this.sendCurrency = sendCurrency ?? this.sendCurrency;
    this.payoutCurrency = payoutCurrency ?? this.payoutCurrency;
    this.sendAmount = sendAmount ?? this.sendAmount;
    _debounce?.cancel();
    if (this.sendAmount <= 0) {
      quote = null;
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), refreshQuote);
  }

  Future<void> refreshQuote() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      quote = await api.getQuote(
        sourceCountry: sourceCountry,
        destCountry: destCountry,
        sendCurrency: sendCurrency,
        payoutCurrency: payoutCurrency,
        sendAmount: sendAmount,
      );
    } on ApiException catch (e) {
      quote = null;
      error = e.toString();
    } catch (_) {
      quote = null;
      error = 'Network error — check connection';
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> submitTransfer({
    required String recipientPhone,
    required String recipientFullName,
  }) async {
    if (quote == null) return false;
    loading = true;
    error = null;
    notifyListeners();
    try {
      transaction = await api.createTransfer(
        quoteId: quote!['quote_id'],
        recipientPhone: recipientPhone,
        recipientFullName: recipientFullName,
      );
      loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e.toString();
      loading = false;
      notifyListeners();
      return false;
    }
  }
}
