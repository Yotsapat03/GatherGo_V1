import 'package:flutter/material.dart';

// ===== ADMIN (prefix กันชนชื่อ) =====
import 'admin/welcome_page/welcome.dart' as w;
import 'admin/welcome_page/admin_home.dart' as ah;
import 'admin/welcome_page/role_page.dart' as rp;
import 'admin/welcome_page/login.dart' as lg;

// ===== ADMIN PAGES =====
import 'admin/bigevent/bigevent_list_page.dart';
import 'admin/bigevent/add_organizer_page.dart';
import 'admin/bigevent/organizer_detail_page.dart';
import 'admin/event_report/event_report_page.dart';
import 'admin/user/user_list_page.dart';
import 'admin/audit_log/audit_log_select_page.dart';
import 'admin/audit_log/admin_audit_log_page.dart';
import 'admin/audit_log/user_audit_log_page.dart';
import 'admin/moderation/admin_spot_chat_moderation_queue_page.dart';

// ===== USER PAGES =====
import 'user/home.dart';
import 'user/spot/spot.dart';
import 'user/joined_event/joined_event.dart';
import 'user/spot/joined_spot.dart';
import 'user/spot/spot_detail_page.dart';
import 'user/status/success.dart';
import 'user/my_spot/my_spot_list_page.dart';
import 'user/my_spot/create_spot_page.dart';
import 'user/my_event/my_event_page.dart';
import 'user/my_event/my_event_task_detail_page.dart';
import 'user/spot/spot_chat_group_page.dart';
import 'user/big_event/big_event.dart' as ub;
import 'user/big_event/big_event_list_page.dart' as ubl;
import 'user/booking/booking_page.dart';
import 'user/profile/user_profile_page.dart';
import 'user/auth/signup_step1.dart';
import 'user/auth/signup_step2_password.dart';

// USER EVENT FLOW
import 'user/events/pages/event_join_page.dart';
import 'user/big_event/event_payment_page.dart'
    as bigpay; // ✅ ใช้ไฟล์ใหม่ BIGPAY
import 'user/events/pages/event_evidence_page.dart';

class AppRoutes {
  // ===== COMMON =====
  static const welcome = '/';
  static const role = '/role';
  static const adminLogin = '/admin-login';
  static const adminHome = '/admin-home';

  // ===== USER =====
  static const userHome = '/u/home';
  static const userBigEvent = '/u/bigEvent';
  static const userJoinedEvent = '/u/joinedEvent';
  static const userSpot = '/u/spot';
  static const userJoinedSpot = '/u/joinedSpot';
  static const userSpotDetail = '/u/spot/detail';
  static const userSuccess = '/u/success';

  static const userMySpot = '/u/mySpot';
  static const userCreateSpot = '/u/mySpot/create';
  static const userMyEvent = '/u/myEvent';
  static const userMyEventDetail = '/u/myEvent/detail';
  static const userSpotChatGroup = '/u/spot/chat-group';
  static const userProfile = '/u/profile';
  static const userBooking = '/u/booking';

  static const userEventJoin = '/u/event/join';
  static const userEventPayment = '/u/event/payment';
  static const userEventEvidence = '/u/event/evidence';
  static const userSignupStep1 = '/u/auth/signup-step1';
  static const userSignupStep2 = '/u/auth/signup-step2';

  // ===== ALIAS (LEGACY) =====
  static const legacyBigEvent = '/bigEvent';
  static const legacyEventJoin = '/eventJoin';
  static const legacyEventPayment = '/eventPayment';
  static const legacyEventEvidence = '/eventEvidence';

  // ===== ADMIN =====
  static const bigEventList = '/big-event-list';
  static const addOrganizer = '/add-organizer';
  static const organizerDetail = '/organizer-detail';
  static const adminEventReport = '/admin-event-report';
  static const userList = '/user-list';
  static const auditLogSelect = '/audit';
  static const adminAuditLog = '/audit/admin';
  static const userAuditLog = '/audit/user';
  static const adminSpotChatModeration = '/admin/spot-chat-moderation';

  // ===== ROUTE MAP (ไม่มี required params) =====
  static final Map<String, WidgetBuilder> routes = {
    // ================= ADMIN =================
    welcome: (_) => const w.WelcomePage(),
    adminHome: (_) => const ah.AdminHomePage(),

    // ================= USER =================
    userHome: (_) => const HomePage(),
    userBigEvent: (_) => const ubl.BigEventListPage(),
    userJoinedEvent: (_) => const JoinedEventPage(),
    userSpot: (_) => const SpotPage(),
    userJoinedSpot: (_) => const JoinedSpotPage(),
    userSpotDetail: (_) => const SpotDetailPage(),
    userMySpot: (_) => const MySpotListPage(),
    userCreateSpot: (_) => const CreateSpotPage(),
    userMyEvent: (_) => const MyEventPage(),
    userMyEventDetail: (_) => const MyEventTaskDetailPage(),
    userSpotChatGroup: (_) => const SpotChatGroupPage(),
    userProfile: (_) => const UserProfilePage(),
    userBooking: (_) => const BookingPage(),
    userSignupStep1: (_) => const SignupStep1Page(),

    // ✅ legacy bigEvent (ไม่มี required args)
    legacyBigEvent: (_) => const ub.BigEventPage(),

    // ================= ADMIN ROUTES =================
    bigEventList: (_) => const BigEventListPage(),
    addOrganizer: (_) => const AddOrganizerPage(),
    organizerDetail: (_) => const OrganizerDetailPage(),
    adminEventReport: (_) => const AdminEventReportPage(),
    userList: (_) => const UserListPage(),
    auditLogSelect: (_) => const AuditLogSelectPage(),
    adminAuditLog: (_) => const AdminAuditLogPage(),
    userAuditLog: (_) => const UserAuditLogPage(),
    adminSpotChatModeration: (_) => const AdminSpotChatModerationQueuePage(),
  };

  // ===== ROUTES ที่มี REQUIRED PARAM / ต้องรับ settings.arguments =====
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ---------- AUTH/COMMON ----------
      case role:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => rp.RolePage(
              isSignUp: args['isSignUp'] == true,
              postLogin: args['postLogin'] == true,
              selectedRole: (args['selectedRole'] ?? 'user').toString(),
              user: args['user'] is Map<String, dynamic>
                  ? args['user'] as Map<String, dynamic>
                  : const {},
            ),
          );
        }

      case adminLogin:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => lg.AdminLoginPage(
              isSignUp: args['isSignUp'] == true,
              selectedRole: (args['selectedRole'] ?? 'admin').toString(),
              prefillEmail: (args['prefillEmail'] ?? '').toString(),
            ),
          );
        }

      case userSignupStep2:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => SignupStep2PasswordPage(signupData: args),
          );
        }

      case userSuccess:
        {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => SuccessPage(
              title: (args['title'] ?? 'Success').toString(),
              subtitle: (args['subtitle'] ?? 'completed').toString(),
              buttonText: (args['buttonText'] ?? 'Back').toString(),
              titleKey: args['titleKey'] as String?,
              subtitleKey: args['subtitleKey'] as String?,
              buttonTextKey: args['buttonTextKey'] as String?,
              popUntilRouteName: args['popUntilRouteName'] as String?,
              blockSystemBack: args['blockSystemBack'] == true,
              autoSeconds: args['autoSeconds'] is int
                  ? args['autoSeconds']
                  : int.tryParse((args['autoSeconds'] ?? '').toString()),
            ),
          );
        }

      // ---------- USER EVENT FLOW ----------
      case userEventJoin:
      case legacyEventJoin:
        {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const EventJoinPage(),
          );
        }

      case userEventPayment:
      case legacyEventPayment:
        {
          // ✅ ชี้ไปหน้า Payment ตัวใหม่ (BIGPAY) ชัวร์ ๆ
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const bigpay.EventPaymentPage(),
          );
        }

      case userEventEvidence:
      case legacyEventEvidence:
        {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const EventEvidencePage(),
          );
        }

      default:
        return null;
    }
  }
}
