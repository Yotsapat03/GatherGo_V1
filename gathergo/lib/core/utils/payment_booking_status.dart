class PaymentStatusValue {
  static const String pending = 'pending';
  static const String awaitingPayment = 'awaiting_payment';
  static const String awaitingManualReview = 'awaiting_manual_review';
  static const String paid = 'paid';
  static const String failed = 'failed';
  static const String manualConfirm = 'manual_confirm';
  static const String cancelled = 'cancelled';
}

class BookingStatusValue {
  static const String pending = 'pending';
  static const String awaitingPayment = 'awaiting_payment';
  static const String confirmed = 'confirmed';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
  static const String canceled = 'canceled';
}

class PaymentBookingStatus {
  static const List<String> _paymentSuccessStatuses = <String>[
    PaymentStatusValue.paid,
    'completed',
    'success',
    'succeeded',
    'done',
  ];

  static const List<String> _bookingConfirmedStatuses = <String>[
    BookingStatusValue.confirmed,
    'paid',
    'completed',
    'success',
  ];

  static String normalize(dynamic raw) {
    return (raw ?? '').toString().trim().toLowerCase();
  }

  static bool _contains(List<String> allowed, dynamic raw) {
    final status = normalize(raw);
    if (status.isEmpty) return false;
    return allowed.any((s) => s == status);
  }

  static bool isPaymentSuccessful(dynamic raw) {
    return _contains(_paymentSuccessStatuses, raw);
  }

  static bool isPaymentManual(dynamic raw) {
    final normalized = normalize(raw);
    return normalized == PaymentStatusValue.manualConfirm ||
        normalized == PaymentStatusValue.awaitingManualReview;
  }

  static bool isBookingConfirmed(dynamic raw) {
    return _contains(_bookingConfirmedStatuses, raw);
  }

  static bool isBookingCancelled(dynamic raw) {
    final normalized = normalize(raw);
    return normalized == BookingStatusValue.cancelled ||
        normalized == BookingStatusValue.canceled;
  }
}
