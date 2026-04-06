/// Application Constants and Configuration
/// Centralized constants for the entire app
library;

const String appName = 'GatherGo';
const String appVersion = '1.0.0';

/// Feature Flags
const bool enablePaymentQR = true;
const bool enableSpotCreation = true;
const bool enableChatRoom = false; // TODO: Implement

/// API Constants
const String apiVersion = 'v1';
const Duration defaultRequestTimeout = Duration(seconds: 30);

/// Payment Methods
const List<String> paymentMethods = ['promptPay', 'stripe'];

/// Currency
const String defaultCurrency = 'THB';

/// Image Upload Limits
const int maxImageSizeBytes = 5 * 1024 * 1024; // 5MB
const int maxEventImages = 10;
const int imageQuality = 85;

/// User Roles
const String roleAdmin = 'admin';
const String roleOrganizer = 'organizer';
const String roleUser = 'user';
const String roleRunner = 'runner';

/// Event Types
const String eventTypeBigEvent = 'BIG_EVENT';
const String eventTypeSpot = 'SPOT';

/// Event Status
enum EventStatus {
  draft,
  published,
  closed,
  cancelled,
}

/// Payment Status
enum PaymentStatus {
  pending,
  awaitingPayment,
  paid,
  failed,
  manualConfirm,
}

/// Booking Status
enum BookingStatus {
  pending,
  awaitingPayment,
  confirmed,
  failed,
  cancelled,
}

/// Event Visibility
enum EventVisibility {
  public,
  private,
}

/// Page Routes (duplicated from app_routes.dart for reference)
/// Use AppRoutes from main routing instead
