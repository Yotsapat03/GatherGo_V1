import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/payment_booking_status.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';

class PaymentResultPage extends StatefulWidget {
  final int paymentId;
  final String eventTitle;
  final num amount;
  final String currency;
  final String fallbackMethodLabel;
  final String fallbackStatusLabel;
  final String? autoRedirectRoute;
  final int autoRedirectSeconds;

  const PaymentResultPage({
    super.key,
    required this.paymentId,
    required this.eventTitle,
    required this.amount,
    required this.currency,
    required this.fallbackMethodLabel,
    required this.fallbackStatusLabel,
    this.autoRedirectRoute,
    this.autoRedirectSeconds = 0,
  });

  @override
  State<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends State<PaymentResultPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _payment = <String, dynamic>{};
  Timer? _redirectTimer;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _load();
    _scheduleAutoRedirect();
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _redirectTimer?.cancel();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = await SessionService.getCurrentUserId();
      if (userId == null || userId <= 0) {
        setState(() {
          _loading = false;
          _error = tr('no_active_user_session');
        });
        return;
      }
      final baseUrl = ConfigService.getBaseUrl();
      final uri = Uri.parse(
          '$baseUrl/api/payments/${widget.paymentId}?user_id=$userId');
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'x-user-id': userId.toString(),
      });
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = tr('load_failed', params: {'error': '${res.statusCode}'});
        });
        return;
      }
      setState(() {
        _payment = jsonDecode(res.body) as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = tr('load_failed', params: {'error': '$e'});
      });
    }
  }

  void _scheduleAutoRedirect() {
    final route = widget.autoRedirectRoute;
    if (route == null || route.isEmpty || widget.autoRedirectSeconds <= 0) {
      return;
    }
    _redirectTimer?.cancel();
    _redirectTimer = Timer(
      Duration(seconds: widget.autoRedirectSeconds),
      _redirectToNextRoute,
    );
  }

  void _redirectToNextRoute() {
    final route = widget.autoRedirectRoute;
    if (!mounted || _redirected || route == null || route.isEmpty) return;
    _redirected = true;
    Navigator.pushNamedAndRemoveUntil(context, route, (route) => false);
  }

  String _displayMethod(String value) {
    switch (value.trim().toUpperCase()) {
      case 'PROMPTPAY':
        return 'PromptPay';
      default:
        return value.trim().isEmpty ? '-' : value.trim();
    }
  }

  String _displayProvider(String value) {
    switch (value.trim().toUpperCase()) {
      case 'STRIPE':
        return 'Stripe';
      case 'MANUAL_QR':
        return 'Manual QR';
      default:
        return value.trim().isEmpty ? '-' : value.trim();
    }
  }

  Future<void> _openReceiptUrl(BuildContext context, String rawUrl) async {
    final receiptUrl = rawUrl.trim();
    if (receiptUrl.isEmpty) return;

    final uri = Uri.tryParse(receiptUrl);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Unable to open receipt')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventTitle =
        (_payment['event_title'] ?? widget.eventTitle).toString();
    final amount = (_payment['amount'] ?? widget.amount).toString();
    final currency =
        (_payment['currency'] ?? widget.currency).toString().toUpperCase();
    final methodType =
        (_payment['method_type'] ?? widget.fallbackMethodLabel).toString();
    final provider = (_payment['provider'] ?? '').toString();
    final status = PaymentBookingStatus.normalize(
      _payment['status'] ?? widget.fallbackStatusLabel,
    );
    final statusText = status.isEmpty ? PaymentStatusValue.pending : status;
    final paidAt = (_payment['paid_at'] ?? '').toString();
    final paymentReference = (_payment['payment_reference'] ?? '').toString();
    final providerTxnId = (_payment['provider_txn_id'] ?? '').toString();
    final receiptNo = (_payment['receipt_no'] ?? '').toString();
    final receiptDate = (_payment['receipt_issue_date'] ?? '').toString();
    final receiptUrl = (_payment['receipt_url'] ?? '').toString();
    final isPaid = PaymentBookingStatus.isPaymentSuccessful(statusText);
    final showAutoRedirectSuccess = isPaid &&
        (widget.autoRedirectRoute ?? '').isNotEmpty &&
        widget.autoRedirectSeconds > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(showAutoRedirectSuccess
            ? tr('payment_successful_title')
            : tr('payment_result_title')),
        automaticallyImplyLeading: !showAutoRedirectSuccess,
      ),
      body: _loading && !showAutoRedirectSuccess
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _error != null
                  ? Text(_error!, style: const TextStyle(color: Colors.red))
                  : showAutoRedirectSuccess
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border:
                                    Border.all(color: const Color(0xFFE6EAF2)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 72,
                                    color: Color(0xFF00C9A7),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    tr('payment_successful_title'),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    eventTitle,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(tr('amount_paid') +
                                      ': $amount $currency'),
                                  Text(
                                      '${tr('payment_method')}: ${_displayMethod(methodType)} / ${_displayProvider(provider)}'),
                                  Text('${tr('status')}: $statusText'),
                                  if (paymentReference.isNotEmpty)
                                    Text(
                                        '${tr('payment_reference')}: $paymentReference'),
                                  if (providerTxnId.isNotEmpty)
                                    Text(
                                        '${tr('transaction_reference')}: $providerTxnId'),
                                  if (paidAt.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('${tr('payment_date')}: $paidAt'),
                                  ],
                                  if (receiptNo.isNotEmpty)
                                    Text(
                                        '${tr('receipt_reference')}: $receiptNo'),
                                  if (receiptUrl.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _openReceiptUrl(context, receiptUrl),
                                      icon: const Icon(
                                          Icons.receipt_long_outlined),
                                      label: Text(tr('open_receipt')),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  Text(
                                    tr(
                                      'redirecting_to_my_event_in_seconds',
                                      params: {
                                        'seconds':
                                            '${widget.autoRedirectSeconds}',
                                      },
                                    ),
                                    textAlign: TextAlign.center,
                                    style:
                                        const TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(eventTitle,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            Text('${tr('amount_paid')}: $amount $currency'),
                            Text(
                                '${tr('payment_method')}: ${_displayMethod(methodType)}'),
                            if (provider.isNotEmpty)
                              Text(
                                  '${tr('payment_provider')}: ${_displayProvider(provider)}'),
                            Text('${tr('status')}: $statusText'),
                            if (paymentReference.isNotEmpty)
                              Text(
                                  '${tr('payment_reference')}: $paymentReference'),
                            if (providerTxnId.isNotEmpty)
                              Text(
                                  '${tr('transaction_reference')}: $providerTxnId'),
                            if (paidAt.isNotEmpty)
                              Text('${tr('payment_date')}: $paidAt'),
                            if (receiptNo.isNotEmpty)
                              Text('${tr('receipt_reference')}: $receiptNo'),
                            if (receiptDate.isNotEmpty)
                              Text('${tr('receipt_date')}: $receiptDate'),
                            if (receiptUrl.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openReceiptUrl(context, receiptUrl),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: Text(tr('open_receipt')),
                              ),
                              const SizedBox(height: 6),
                              SelectableText('Receipt: $receiptUrl'),
                            ],
                          ],
                        ),
            ),
    );
  }
}
