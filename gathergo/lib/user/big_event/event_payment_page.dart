import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/payment_booking_status.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import 'browser_return_listener_stub.dart'
    if (dart.library.html) 'browser_return_listener_web.dart';
import 'payment_result_page.dart';

enum ManualMethodType { promptpay }

enum StripeMethodType { promptpay }

class EventPaymentPage extends StatefulWidget {
  const EventPaymentPage({super.key});

  @override
  State<EventPaymentPage> createState() => _EventPaymentPageState();
}

class _EventPaymentPageState extends State<EventPaymentPage>
    with WidgetsBindingObserver {
  static const List<String> _defaultShirtSizes = <String>[
    'XS',
    'S',
    'M',
    'L',
    'XL',
  ];

  bool _inited = false;
  bool _loadingMethods = false;
  bool _processing = false;

  late String _baseUrl = ConfigService.getBaseUrl();
  Map<String, dynamic> _event = <String, dynamic>{};
  int _eventId = 0;
  int _userId = 0;
  num _amount = 0;
  String _currency = 'THB';
  String _eventTitle = 'Big Event';
  String? _eventDate;
  String _paymentMode = 'manual_qr';
  String? _selectedShirtSize;

  bool _manualPromptpayEnabled = false;
  bool _stripePromptpayEnabled = false;
  String? _manualPromptpayQrUrl;
  num? _promptpayAmountThb;

  ManualMethodType? _selectedManualMethod;
  StripeMethodType? _selectedStripeMethod;
  XFile? _selectedSlipFile;
  int? _bookingId;
  int? _currentPaymentId;
  String? _error;
  String? _stripeRedirectUrl;
  String? _stripeQrImageUrl;
  bool _stripeQrPreviewFailed = false;
  bool _stripeHostedPageOpened = false;
  Timer? _stripeStatusPollTimer;
  bool _stripeStatusPending = false;
  bool _navigatingToPaymentResult = false;
  bool _stripeStatusCheckInFlight = false;
  String? _lastLoggedStripeStatus;
  String _currentHostedProvider = 'stripe';
  String _currentHostedProviderLabel = 'Stripe';
  final BrowserReturnListener _browserReturnListener = BrowserReturnListener();

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  bool get _hasEventPayloadForRendering => _eventId > 0;

  bool get _hasRequiredCheckoutContext =>
      _eventId > 0 && _userId > 0 && _hasEventPayloadForRendering;

  bool get _hasValidManualPaymentContext {
    if (!(_paymentMode == 'manual_qr' || _paymentMode == 'hybrid')) return true;
    final hasPromptpayQr = _manualPromptpayEnabled &&
        (_manualPromptpayQrUrl ?? '').trim().isNotEmpty;
    final hasManualMethod = hasPromptpayQr;
    final hasManualQr = hasManualMethod;
    return _hasRequiredCheckoutContext && hasManualMethod && hasManualQr;
  }

  bool get _shouldShowInvalidContextFallback => !_hasRequiredCheckoutContext;

  List<Map<String, dynamic>> get _guaranteedRewardItems {
    final raw = _event['guaranteed_items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool get _requiresShirtSize {
    if (_event['requires_shirt_size'] == true) return true;
    for (final item in _guaranteedRewardItems) {
      final type = (item['item_type'] ?? item['itemType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (type == 'shirt') return true;
    }
    return false;
  }

  List<String> get _shirtSizeOptions {
    final raw = _event['shirt_size_options'];
    if (raw is List) {
      final values = raw
          .map((item) => item.toString().trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isNotEmpty) return values;
    }
    return _defaultShirtSizes;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _bootstrap();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    if (kIsWeb) {
      _browserReturnListener.attach(_handleStripeReturnSignal);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _browserReturnListener.dispose();
    _stopStripeStatusPolling();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    debugPrint('[StripePaymentUI] app-return state=resumed');
    _handleStripeReturnSignal();
  }

  Future<void> _bootstrap() async {
    final args =
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ??
            {};

    final incomingBaseUrl =
        (args['baseUrl'] ?? args['base_url'] ?? '').toString().trim();
    if (incomingBaseUrl.isNotEmpty) _baseUrl = incomingBaseUrl;

    _event = (args['event'] is Map)
        ? Map<String, dynamic>.from(args['event'])
        : <String, dynamic>{};
    _eventId = int.tryParse(
          (args['eventId'] ??
                  args['event_id'] ??
                  _event['id'] ??
                  _event['event_id'] ??
                  '')
              .toString(),
        ) ??
        0;
    _eventTitle = (args['eventTitle'] ??
            args['event_title'] ??
            _event['title'] ??
            'Big Event')
        .toString();
    _eventDate = (args['eventDate'] ??
            args['event_date'] ??
            _event['start_at'] ??
            _event['event_date'] ??
            _event['date'])
        ?.toString();
    _amount = _toNum(
      args['amount'] ?? args['price'] ?? _event['fee'] ?? _event['price'] ?? 0,
    );
    _currency = (args['currency'] ?? _event['currency'] ?? 'THB')
        .toString()
        .toUpperCase();
    _bookingId = int.tryParse(
      (args['bookingId'] ?? args['booking_id'] ?? '').toString(),
    );
    _userId = int.tryParse(
          (args['userId'] ?? args['user_id'] ?? '').toString(),
        ) ??
        0;
    _paymentMode = (args['paymentMode'] ??
            args['payment_mode'] ??
            _event['payment_mode'] ??
            _paymentMode)
        .toString();
    final incomingShirtSize = (args['shirt_size'] ?? _event['shirt_size'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (incomingShirtSize.isNotEmpty) {
      _selectedShirtSize = incomingShirtSize;
    }
    if (_userId <= 0) {
      _userId = await SessionService.getCurrentUserId() ?? 0;
    }
    debugPrint(
      '[BigEventPayment] context eventId=$_eventId userId=$_userId '
      'bookingId=${_bookingId ?? '-'} mode=$_paymentMode amount=$_amount $_currency '
      'title="$_eventTitle"',
    );
    if (!_hasRequiredCheckoutContext) {
      setState(() {
        _error = tr('payment_context_incomplete');
      });
      return;
    }
    await _loadPaymentMethods();
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _preferNonEmptyString(dynamic primary, String fallback) {
    final value = (primary ?? '').toString().trim();
    return value.isNotEmpty ? value : fallback;
  }

  String? _preferNonEmptyNullableString(dynamic primary, String? fallback) {
    final value = (primary ?? '').toString().trim();
    if (value.isNotEmpty) return value;
    final fallbackValue = (fallback ?? '').trim();
    return fallbackValue.isEmpty ? null : fallbackValue;
  }

  num _preferPositiveOrExistingNum(dynamic primary, num fallback) {
    final parsed = _toNum(primary);
    if (parsed > 0) return parsed;
    return fallback;
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _loadingMethods = true;
      _error = null;
      _manualPromptpayEnabled = false;
      _stripePromptpayEnabled = false;
      _selectedManualMethod = null;
      _selectedStripeMethod = null;
      _manualPromptpayQrUrl = null;
    });
    try {
      final uri =
          Uri.parse('$_baseUrl/api/big-events/$_eventId/payment-methods');
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'x-user-id': _userId.toString(),
      });
      final body = res.body;
      if (res.statusCode != 200) {
        setState(() {
          _loadingMethods = false;
          _error = _extractMessage(body) ??
              'Load methods failed (${res.statusCode})';
        });
        return;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final eventPayload = (decoded['event'] is Map)
          ? Map<String, dynamic>.from(decoded['event'] as Map)
          : <String, dynamic>{};
      final methods = (decoded['methods'] is List)
          ? List<Map<String, dynamic>>.from(decoded['methods'] as List)
          : <Map<String, dynamic>>[];

      final nextEventTitle =
          _preferNonEmptyString(eventPayload['title'], _eventTitle);
      final nextEventDate = _preferNonEmptyNullableString(
        eventPayload['start_at'] ??
            eventPayload['event_date'] ??
            eventPayload['date'],
        _eventDate,
      );
      final nextAmount =
          _preferPositiveOrExistingNum(eventPayload['fee'], _amount);
      final nextCurrency =
          _preferNonEmptyString(eventPayload['currency'], _currency)
              .toUpperCase();
      num nextPromptpayAmountThb = _toNum(
        eventPayload['promptpay_amount_thb'] ?? eventPayload['fee'] ?? _amount,
      );
      final nextPaymentMode =
          _preferNonEmptyString(eventPayload['payment_mode'], _paymentMode);
      String? nextManualPromptpayQrUrl =
          (eventPayload['manual_promptpay_qr_url'] ?? '').toString().trim();
      if ((nextManualPromptpayQrUrl ?? '').isEmpty) {
        nextManualPromptpayQrUrl = null;
      }

      bool manualPromptpay = false;
      bool stripePromptpay = false;

      for (final method in methods) {
        final type = (method['method_type'] ?? '').toString().toUpperCase();
        if (type == 'PROMPTPAY') {
          manualPromptpay = method['manual_available'] == true;
          stripePromptpay = method['stripe_available'] == true;
          nextPromptpayAmountThb =
              _toNum(method['amount'] ?? nextPromptpayAmountThb ?? nextAmount);
          if (((method['qr_image_url'] ?? '').toString()).isNotEmpty &&
              (nextManualPromptpayQrUrl ?? '').isEmpty) {
            nextManualPromptpayQrUrl =
                (method['qr_image_url'] ?? '').toString();
          }
        }
      }

      setState(() {
        _event = <String, dynamic>{
          ..._event,
          ...eventPayload,
        };
        _eventTitle = nextEventTitle;
        _eventDate = nextEventDate;
        _amount = nextAmount;
        _currency = nextCurrency;
        _promptpayAmountThb = nextPromptpayAmountThb;
        _paymentMode = nextPaymentMode;
        _manualPromptpayQrUrl = nextManualPromptpayQrUrl;
        _manualPromptpayEnabled = manualPromptpay;
        _stripePromptpayEnabled = stripePromptpay;
        if (_requiresShirtSize &&
            _selectedShirtSize != null &&
            !_shirtSizeOptions.contains(_selectedShirtSize)) {
          _selectedShirtSize = null;
        }
        _selectedManualMethod =
            manualPromptpay ? ManualMethodType.promptpay : null;
        _selectedStripeMethod =
            stripePromptpay ? StripeMethodType.promptpay : null;
        final hasAnyMethod = manualPromptpay || stripePromptpay;
        _error = !_hasRequiredCheckoutContext
            ? tr('payment_context_incomplete')
            : !hasAnyMethod
                ? tr('no_payment_methods_available')
                : ((_paymentMode == 'manual_qr' || _paymentMode == 'hybrid') &&
                        !_hasValidManualPaymentContext)
                    ? tr('manual_payment_not_fully_configured')
                    : null;
        _loadingMethods = false;
      });
    } catch (e) {
      setState(() {
        _loadingMethods = false;
        _manualPromptpayEnabled = false;
        _stripePromptpayEnabled = false;
        _selectedManualMethod = null;
        _selectedStripeMethod = null;
        _manualPromptpayQrUrl = null;
        _error = 'Load payment methods failed: $e';
      });
    }
  }

  Future<void> _pickSlip() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _selectedSlipFile = file);
  }

  bool _validateShirtSizeSelection() {
    if (!_requiresShirtSize) return true;
    if ((_selectedShirtSize ?? '').trim().isNotEmpty) return true;
    _showSnack(tr('shirt_size_required'));
    return false;
  }

  Future<int?> _ensureBooking() async {
    if (!_validateShirtSizeSelection()) return null;
    if (_bookingId != null && _bookingId! > 0 && !_requiresShirtSize) {
      return _bookingId;
    }
    final uri = Uri.parse('$_baseUrl/api/big-events/$_eventId/bookings');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-user-id': _userId.toString(),
      },
      body: jsonEncode({
        'user_id': _userId,
        'quantity': 1,
        'shirt_size': _selectedShirtSize,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractMessage(res.body) ??
          'Create booking failed (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final bookingId = int.tryParse(
        (decoded['bookingId'] ?? decoded['booking_id'] ?? '').toString());
    if (bookingId == null || bookingId <= 0) {
      throw Exception('Booking ID missing from backend response');
    }
    setState(() => _bookingId = bookingId);
    return bookingId;
  }

  int? _parsePaymentId(Map<String, dynamic> decoded) {
    return int.tryParse(
      (decoded['payment_id'] ?? decoded['paymentId'] ?? '').toString(),
    );
  }

  void _handleStripeReturnSignal() {
    if (!_stripeHostedPageOpened || !_stripeStatusPending) return;
    if (_currentPaymentId == null || _currentPaymentId! <= 0) return;
    debugPrint(
      '[StripePaymentUI] return-detected paymentId=$_currentPaymentId pending=$_stripeStatusPending',
    );
    unawaited(_checkStripeStatus(triggeredByReturn: true));
  }

  void _stopStripeStatusPolling() {
    _stripeStatusPollTimer?.cancel();
    _stripeStatusPollTimer = null;
  }

  void _startStripeStatusPolling() {
    if (_navigatingToPaymentResult || _stripeStatusPending == false) return;
    if (_currentPaymentId == null || _currentPaymentId! <= 0) return;
    if (_stripeStatusPollTimer != null) return;
    _stripeStatusPollTimer =
        Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted ||
          _currentPaymentId == null ||
          _processing ||
          _navigatingToPaymentResult ||
          !_stripeStatusPending) {
        return;
      }
      await _checkStripeStatus(silent: true);
    });
  }

  Future<void> _openStripeHostedPage() async {
    final redirectUrl = (_stripeRedirectUrl ?? '').trim();
    if (redirectUrl.isEmpty) return;
    final providerLabel = _currentHostedProviderLabel;
    debugPrint(
      '[StripePaymentUI] hosted-page launch provider=$providerLabel paymentId=${_currentPaymentId ?? '-'} mode=${kIsWeb ? 'platformDefault' : 'externalApplication'}',
    );
    final ok = await launchUrl(
      Uri.parse(redirectUrl),
      mode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!mounted) return;
    if (ok) {
      debugPrint(
        '[StripePaymentUI] hosted-page provider=$providerLabel paymentId=${_currentPaymentId ?? '-'} url=open',
      );
      setState(() => _stripeHostedPageOpened = true);
    } else {
      _showSnack('Unable to open $providerLabel payment page');
    }
  }

  Future<void> _submitManualSlip() async {
    if (_processing) return;
    if (!_validateShirtSizeSelection()) return;
    if (_selectedManualMethod == null) {
      _showSnack('Select one manual payment method');
      return;
    }
    if (_selectedSlipFile == null) {
      _showSnack('Upload payment slip first');
      return;
    }

    setState(() => _processing = true);
    try {
      final bookingId = await _ensureBooking();
      if (bookingId == null || bookingId <= 0) {
        throw Exception('Booking unavailable');
      }

      final uri = Uri.parse('$_baseUrl/api/bookings/$bookingId/payment-slip');
      const paymentMethod = 'promptpay';
      const fallbackMethodLabel = 'PROMPTPAY';
      const fallbackCurrency = 'THB';
      final fallbackAmount = (_promptpayAmountThb ?? _amount);
      final req = http.MultipartRequest('POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['x-user-id'] = _userId.toString()
        ..fields['payment_method'] = paymentMethod
        ..fields['user_id'] = _userId.toString();

      if (kIsWeb) {
        final bytes = await _selectedSlipFile!.readAsBytes();
        req.files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: _selectedSlipFile!.name));
      } else {
        req.files.add(
            await http.MultipartFile.fromPath('file', _selectedSlipFile!.path));
      }

      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception(_extractMessage(body) ??
            'Slip upload failed (${streamed.statusCode})');
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final paymentId = _parsePaymentId(decoded);
      if (paymentId == null || paymentId <= 0) {
        throw Exception('Payment ID missing after slip upload');
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentResultPage(
            paymentId: paymentId,
            eventTitle: _eventTitle,
            amount: fallbackAmount,
            currency: fallbackCurrency,
            fallbackMethodLabel: fallbackMethodLabel,
            fallbackStatusLabel: 'awaiting_manual_review',
          ),
        ),
      );
    } catch (e) {
      _showSnack('Manual payment failed: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _startStripeCheckout() async {
    if (_processing) return;
    if (!_validateShirtSizeSelection()) return;
    if (_selectedStripeMethod == null) {
      _showSnack('Select one Stripe payment method');
      return;
    }
    if (_eventId <= 0) {
      _showSnack(
          'Payment information is incomplete. Please return to the event and try again.');
      return;
    }
    _stopStripeStatusPolling();

    setState(() {
      _processing = true;
      _stripeRedirectUrl = null;
      _stripeQrImageUrl = null;
      _stripeQrPreviewFailed = false;
      _stripeHostedPageOpened = false;
      _currentHostedProviderLabel = 'Stripe';
    });

    try {
      const methodType = 'promptpay';
      const providerLabel = 'Stripe';
      const createPath = '/api/stripe/create-payment-intent';
      debugPrint(
        '[StripePaymentUI] start eventId=$_eventId bookingId=${_bookingId ?? '-'} method=$methodType provider=$providerLabel',
      );
      final uri = Uri.parse('$_baseUrl$createPath');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-user-id': _userId.toString(),
        },
        body: jsonEncode({
          'event_id': _eventId,
          'selected_payment_method_type': methodType,
          'shirt_size': _selectedShirtSize,
          'client_platform': kIsWeb ? 'web' : 'mobile',
          'os_type': _detectOsType(),
        }),
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(_extractMessage(res.body) ??
            '$providerLabel checkout failed (${res.statusCode})');
      }

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final paymentId = _parsePaymentId(decoded);
      final provider =
          (decoded['provider'] ?? '').toString().trim().toLowerCase();
      final providerLabelFromApi =
          (decoded['provider_label'] ?? '').toString().trim();
      final paymentIntentId =
          (decoded['payment_intent_id'] ?? decoded['paymentIntentId'] ?? '')
              .toString()
              .trim();
      final clientSecret = (decoded['client_secret'] ?? '').toString().trim();
      final paymentStatus =
          (decoded['status'] ?? '').toString().trim().toLowerCase();
      final nextAction = decoded['nextAction'] is Map
          ? Map<String, dynamic>.from(decoded['nextAction'] as Map)
          : decoded['next_action'] is Map
              ? Map<String, dynamic>.from(decoded['next_action'] as Map)
              : <String, dynamic>{};
      final checkoutUrl = ((decoded['checkout_url'] ??
                  decoded['checkoutUrl'] ??
                  '')
              .toString()
              .trim()
              .isNotEmpty)
          ? (decoded['checkout_url'] ?? decoded['checkoutUrl'])
              .toString()
              .trim()
          : ((decoded['redirect_url'] ?? decoded['redirectUrl'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty)
              ? (decoded['redirect_url'] ?? decoded['redirectUrl'])
                  .toString()
                  .trim()
              : ((decoded['qr_url'] ?? decoded['qrUrl'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
                  ? (decoded['qr_url'] ?? decoded['qrUrl']).toString().trim()
                  : _readNestedString(nextAction, ['redirect_to_url', 'url']) ??
                      _readNestedString(nextAction, [
                        'promptpay_display_qr_code',
                        'hosted_instructions_url'
                      ]) ??
                      '';
      final qrImageUrl = ((decoded['qr_image_url'] ?? decoded['qrImage'] ?? '')
              .toString()
              .trim()
              .isNotEmpty)
          ? (decoded['qr_image_url'] ?? decoded['qrImage']).toString().trim()
          : _readNestedString(
                  nextAction, ['promptpay_display_qr_code', 'image_url_png']) ??
              '';
      final hasPromptpayQr = qrImageUrl.isNotEmpty ||
          (_readNestedString(nextAction, [
                    'promptpay_display_qr_code',
                    'hosted_instructions_url'
                  ]) ??
                  '')
              .isNotEmpty;
      final hasUsableNextAction = hasPromptpayQr ||
          (_readNestedString(nextAction, ['redirect_to_url', 'url']) ?? '')
              .isNotEmpty;
      final hasValidPendingStatus = _isStripePendingStatus(paymentStatus);

      setState(() {
        _currentPaymentId = paymentId;
        _currentHostedProvider = provider.isNotEmpty ? provider : 'stripe';
        _currentHostedProviderLabel =
            providerLabelFromApi.isNotEmpty ? providerLabelFromApi : 'Stripe';
        _bookingId = int.tryParse((decoded['booking_id'] ?? '').toString()) ??
            _bookingId;
        _stripeRedirectUrl = checkoutUrl.isEmpty ? null : checkoutUrl;
        _stripeQrImageUrl = qrImageUrl.isEmpty ? null : qrImageUrl;
        _stripeQrPreviewFailed = false;
        _stripeStatusPending = paymentStatus != 'succeeded' &&
            (paymentId != null || hasUsableNextAction || hasValidPendingStatus);
      });

      debugPrint(
        '[StripePaymentUI] response paymentId=${paymentId ?? '-'} '
        'provider=${provider.isEmpty ? '-' : provider} '
        'intent=${paymentIntentId.isEmpty ? '-' : paymentIntentId} status=$paymentStatus '
        'hosted=${checkoutUrl.isNotEmpty} qr=${qrImageUrl.isNotEmpty} '
        'nextAction=${nextAction.isNotEmpty} clientSecret=${clientSecret.isNotEmpty}',
      );

      if (paymentStatus == 'succeeded') {
        await _goToStripeSuccess(paymentId);
        return;
      } else if (checkoutUrl.isNotEmpty) {
        await _openStripeHostedPage();
        _startStripeStatusPolling();
      } else if (hasUsableNextAction) {
        _startStripeStatusPolling();
      } else if (hasValidPendingStatus) {
        _startStripeStatusPolling();
        _showSnack(
            '$providerLabel payment is pending. Use Refresh Payment Status.');
      } else {
        _showSnack(
            '$providerLabel created payment but no next action was returned');
      }
    } catch (e) {
      _showSnack(_friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _checkStripeStatus({
    bool silent = false,
    bool triggeredByReturn = false,
  }) async {
    if (_stripeStatusCheckInFlight) {
      debugPrint(
        '[StripePaymentUI] status-check skipped paymentId=${_currentPaymentId ?? '-'} reason=in-flight',
      );
      return;
    }
    if (_currentPaymentId == null || _navigatingToPaymentResult) {
      if (!silent) _showSnack('No Stripe payment to check');
      return;
    }
    _stripeStatusCheckInFlight = true;
    if (!silent && mounted) {
      setState(() => _processing = true);
    }
    try {
      debugPrint(
        '[StripePaymentUI] status-check start paymentId=$_currentPaymentId return=$triggeredByReturn silent=$silent',
      );
      final statusPath = '/api/payments/${_currentPaymentId!}';
      final uri = Uri.parse('$_baseUrl$statusPath?user_id=$_userId');
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'x-user-id': _userId.toString(),
      });
      if (res.statusCode != 200) {
        throw Exception(_extractMessage(res.body) ??
            'Check payment failed (${res.statusCode})');
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final status =
          (decoded['status'] ?? PaymentStatusValue.pending).toString();
      if (!silent || _lastLoggedStripeStatus != status) {
        debugPrint(
          '[StripePaymentUI] status paymentId=$_currentPaymentId status=$status',
        );
        _lastLoggedStripeStatus = status;
      }
      if (PaymentBookingStatus.isPaymentSuccessful(decoded['status'])) {
        _stopStripeStatusPolling();
        _stripeStatusPending = false;
        await _goToStripeSuccess(
          _currentPaymentId!,
          statusLabel:
              (decoded['status'] ?? PaymentStatusValue.paid).toString(),
        );
      } else if (status == 'failed' ||
          status == 'cancelled' ||
          status == 'canceled') {
        _stopStripeStatusPolling();
        _stripeStatusPending = false;
        debugPrint(
          '[StripePaymentUI] payment-terminal paymentId=$_currentPaymentId status=$status',
        );
        if (!silent) {
          _showSnack(_buildPendingPaymentMessage(
            decoded,
            triggeredByReturn: triggeredByReturn,
          ));
        }
      } else {
        _stripeStatusPending = true;
        debugPrint(
          '[StripePaymentUI] payment-pending paymentId=$_currentPaymentId status=$status',
        );
        if (!silent) {
          _showSnack(_buildPendingPaymentMessage(
            decoded,
            triggeredByReturn: triggeredByReturn,
          ));
        }
      }
    } catch (e) {
      debugPrint(
        '[StripePaymentUI] payment-check failed paymentId=${_currentPaymentId ?? '-'} error=$e',
      );
      if (!silent) _showSnack('Check payment error: $e');
    } finally {
      _stripeStatusCheckInFlight = false;
      if (!silent && mounted) setState(() => _processing = false);
    }
  }

  String _buildPendingPaymentMessage(
    dynamic rawStatus, {
    bool triggeredByReturn = false,
  }) {
    final payload =
        rawStatus is Map ? Map<String, dynamic>.from(rawStatus as Map) : null;
    final status = PaymentBookingStatus.normalize(
        payload != null ? payload['status'] : rawStatus);
    if (status == 'failed' || status == 'cancelled' || status == 'canceled') {
      final reason = _preferNonEmptyNullableString(
        payload?['failure_reason'] ?? payload?['message'],
        null,
      );
      return reason ?? 'Payment was not completed. You can try again.';
    }
    if (triggeredByReturn) {
      return 'Payment is still in progress. Please wait a moment and refresh again.';
    }
    return 'Payment in progress (${status.isEmpty ? PaymentStatusValue.pending : status}).';
  }

  Future<void> _refreshJoinedEventState() async {
    final joinedUri =
        Uri.parse('$_baseUrl/api/user/joined-events?user_id=$_userId');
    final eventListUri = Uri.parse('$_baseUrl/api/big-events');
    final responses = await Future.wait([
      http.get(joinedUri, headers: {
        'Accept': 'application/json',
        'x-user-id': _userId.toString(),
      }),
      http.get(eventListUri, headers: {
        'Accept': 'application/json',
        'x-user-id': _userId.toString(),
      }),
    ]);
    for (final res in responses) {
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Refresh failed (${res.statusCode})');
      }
    }
  }

  Future<void> _goToStripeSuccess(int? paymentId, {String? statusLabel}) async {
    if (!mounted ||
        paymentId == null ||
        paymentId <= 0 ||
        _navigatingToPaymentResult) {
      return;
    }
    debugPrint(
      '[StripePaymentUI] payment-confirmed navigate paymentId=$paymentId status=${statusLabel ?? PaymentStatusValue.paid}',
    );
    _navigatingToPaymentResult = true;
    _stripeStatusPending = false;
    _stopStripeStatusPolling();
    try {
      await _refreshJoinedEventState();
    } catch (_) {
      // Best-effort refresh before entering the joined-events area.
    }
    if (!mounted) return;
    await Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.userSuccess,
      (route) => false,
      arguments: {
        'titleKey': 'payment_successful_title',
        'subtitleKey': 'payment_successful_subtitle',
        'buttonTextKey': 'back_to_home',
        'title': 'Payment Successful',
        'subtitle': 'Your payment has been confirmed successfully.',
        'buttonText': 'Back to Home',
        'blockSystemBack': true,
        'autoSeconds': 3,
      },
    );
  }

  String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  bool _isStripePendingStatus(String status) {
    switch (status) {
      case 'processing':
      case 'requires_action':
      case 'requires_payment_method':
        return true;
      default:
        return false;
    }
  }

  String _detectOsType() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'android';
    }
  }

  String? _readNestedString(Map<String, dynamic> source, List<String> path) {
    dynamic current = source;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    final value = current?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSlipPreview() {
    if (_selectedSlipFile == null) {
      return const Text('No slip selected');
    }
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: _selectedSlipFile!.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData &&
              snapshot.connectionState == ConnectionState.done) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  Image.memory(snapshot.data!, height: 160, fit: BoxFit.cover),
            );
          }
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(io.File(_selectedSlipFile!.path),
          height: 160, fit: BoxFit.cover),
    );
  }

  Widget _buildShirtSizeSection() {
    if (!_requiresShirtSize) return const SizedBox.shrink();
    final options = _shirtSizeOptions;
    return _SectionCard(
      title: tr('shirt_size'),
      subtitle: tr('shirt_size_before_checkout'),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: options.map((size) {
          final selected = _selectedShirtSize == size;
          return ChoiceChip(
            label: Text(size),
            selected: selected,
            onSelected: (_) => setState(() => _selectedShirtSize = size),
            selectedColor: const Color(0xFFDDEAFF),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF1D4ED8) : Colors.black87,
            ),
            side: BorderSide(
              color: selected ? const Color(0xFF60A5FA) : Colors.black12,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildManualSection() {
    final canShowManual =
        _paymentMode == 'manual_qr' || _paymentMode == 'hybrid';
    if (!canShowManual || !_hasValidManualPaymentContext)
      return const SizedBox.shrink();

    return _SectionCard(
      title: 'Manual QR Payment',
      subtitle: 'Upload slip. Payment stays in manual review.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_manualPromptpayEnabled)
            RadioListTile<ManualMethodType>(
              value: ManualMethodType.promptpay,
              groupValue: _selectedManualMethod,
              contentPadding: EdgeInsets.zero,
              title: const Text('PromptPay'),
              subtitle: const Text('Scan PromptPay QR and upload slip'),
              onChanged: (v) => setState(() => _selectedManualMethod = v),
            ),
          if (_manualPromptpayEnabled &&
              _selectedManualMethod == ManualMethodType.promptpay &&
              (_manualPromptpayQrUrl ?? '').isNotEmpty)
            _QrCard(title: 'PromptPay QR', imageUrl: _manualPromptpayQrUrl!),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _processing ? null : _pickSlip,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Slip'),
          ),
          const SizedBox(height: 8),
          _buildSlipPreview(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _processing ? null : _submitManualSlip,
              child: const Text('Submit Manual Payment'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStripeSection() {
    final canShowStripe =
        _paymentMode == 'stripe_auto' || _paymentMode == 'hybrid';
    if (!canShowStripe) return const SizedBox.shrink();

    return _SectionCard(
      title: tr('automatic_online_payment'),
      subtitle: tr('stripe_promptpay_auto_subtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stripePromptpayEnabled)
            RadioListTile<StripeMethodType>(
              value: StripeMethodType.promptpay,
              groupValue: _selectedStripeMethod,
              contentPadding: EdgeInsets.zero,
              title: const Text('PromptPay'),
              subtitle: Text(
                  'Stripe PromptPay automatic flow • ${(_promptpayAmountThb ?? _amount).toStringAsFixed(2)} THB'),
              onChanged: (v) => setState(() => _selectedStripeMethod = v),
            ),
          if ((_stripeQrImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildStripeQrCard(),
          ],
          if ((_stripeRedirectUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _currentHostedProvider == 'stripe'
                  ? (_stripeHostedPageOpened
                      ? 'Complete payment on the Stripe page, then return here. The app will refresh automatically.'
                      : 'Use the Stripe payment page if the browser blocks the QR preview.')
                  : (_stripeHostedPageOpened
                      ? 'Complete payment on the $_currentHostedProviderLabel page, then return here. The app will refresh automatically.'
                      : 'Use the $_currentHostedProviderLabel payment page if the browser blocks the redirect preview.'),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _processing ? null : _openStripeHostedPage,
              child: Text(_currentHostedProvider == 'stripe'
                  ? 'Open Stripe payment page again'
                  : 'Open $_currentHostedProviderLabel payment page again'),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_processing || _stripeStatusPending)
                  ? null
                  : _startStripeCheckout,
              child: Text(
                _stripeStatusPending
                    ? tr('stripe_payment_in_progress')
                    : tr('start_stripe_payment'),
              ),
            ),
          ),
          if (_currentPaymentId != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    _navigatingToPaymentResult ? null : _checkStripeStatus,
                child: const Text('Refresh Payment Status'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStripeQrCard() {
    if (_stripeQrPreviewFailed && kIsWeb) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'QR preview unavailable in browser',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _currentHostedProvider == 'stripe'
                  ? 'Browser security may block the Stripe QR preview. Use the Stripe payment page to complete PromptPay payment.'
                  : 'Browser security may block the $_currentHostedProviderLabel QR preview. Use the hosted payment page to continue.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            if ((_stripeRedirectUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _processing ? null : _openStripeHostedPage,
                  child: Text(_currentHostedProvider == 'stripe'
                      ? 'Open Stripe payment page again'
                      : 'Open $_currentHostedProviderLabel payment page again'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return _QrCard(
      title: _currentHostedProvider == 'stripe'
          ? 'Stripe PromptPay QR'
          : '$_currentHostedProviderLabel QR',
      imageUrl: _stripeQrImageUrl!,
      onImageError: () {
        if (!mounted || _stripeQrPreviewFailed) return;
        setState(() => _stripeQrPreviewFailed = true);
      },
      errorFallback:
          kIsWeb ? const SizedBox.shrink() : const Text('Failed to load QR'),
    );
  }

  void _goHomeFromCheckout() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.userHome,
      (route) => false,
    );
  }

  Future<void> _handleFallbackBack() async {
    if (_currentPaymentId != null &&
        _currentPaymentId! > 0 &&
        !_navigatingToPaymentResult) {
      await _checkStripeStatus(silent: true, triggeredByReturn: true);
      if (!mounted || _navigatingToPaymentResult) return;
    }
    _goHomeFromCheckout();
  }

  Widget _buildBottomBackButton() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _handleFallbackBack,
          icon: const Icon(Icons.arrow_back),
          label: Text(tr('back')),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildInvalidContextFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('payment_context_incomplete'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? tr('required_payment_context_missing'),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleFallbackBack,
                  child: Text(_hasEventPayloadForRendering
                      ? tr('back_to_event')
                      : tr('back_to_big_events')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _handleFallbackBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _handleFallbackBack,
          ),
          title: Text(
            tr('checkout_title'),
            style: const TextStyle(color: Colors.black),
          ),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        bottomNavigationBar: _buildBottomBackButton(),
        body: _loadingMethods
            ? const Center(child: CircularProgressIndicator())
            : _shouldShowInvalidContextFallback
                ? _buildInvalidContextFallback()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(_eventTitle,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if ((_eventDate ?? '').isNotEmpty)
                        Text(tr('date_with_value',
                            params: {'value': _eventDate!})),
                      if (_manualPromptpayEnabled || _stripePromptpayEnabled)
                        Text(tr('promptpay_with_value', params: {
                          'value':
                              '${(_promptpayAmountThb ?? _amount).toStringAsFixed(2)} THB',
                        })),
                      const SizedBox(height: 8),
                      Text(tr(
                        'payment_mode_with_value',
                        params: {'value': _paymentMode},
                      )),
                      if (_currentPaymentId != null && _currentPaymentId! > 0)
                        Text(tr(
                          'payment_id_with_value',
                          params: {'value': '$_currentPaymentId'},
                        )),
                      if (_bookingId != null && _bookingId! > 0)
                        Text(tr(
                          'booking_id_with_value',
                          params: {'value': '$_bookingId'},
                        )),
                      const SizedBox(height: 12),
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      _buildShirtSizeSection(),
                      if (_requiresShirtSize) const SizedBox(height: 14),
                      _buildManualSection(),
                      if (_paymentMode == 'hybrid') const SizedBox(height: 14),
                      _buildStripeSection(),
                    ],
                  ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  final String title;
  final String imageUrl;
  final VoidCallback? onImageError;
  final Widget? errorFallback;

  const _QrCard({
    required this.title,
    required this.imageUrl,
    this.onImageError,
    this.errorFallback,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              height: 220,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                if (onImageError != null) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => onImageError!());
                }
                return errorFallback ?? const Text('Failed to load QR');
              },
            ),
          ),
        ],
      ),
    );
  }
}
