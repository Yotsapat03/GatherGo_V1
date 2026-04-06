import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_routes.dart';
import '../../constants/app_assets_keys.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../profile/distance_compare.dart';
import '../profile/user_distance_service.dart';
import '../utils/activity_expiry.dart';
import 'model/chat_message_model.dart';
import 'services/spot_chat_service.dart';
import 'widgets/chat_message_bubble.dart';

class SpotChatGroupPage extends StatefulWidget {
  const SpotChatGroupPage({super.key});

  @override
  State<SpotChatGroupPage> createState() => _SpotChatGroupPageState();
}

class _SpotChatGroupPageState extends State<SpotChatGroupPage> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final SpotChatService _spotChatService;

  List<_ChatMessage> _messages = <_ChatMessage>[];
  final List<_ChatSystemAlert> _systemAlerts = <_ChatSystemAlert>[];
  List<_ChatItem> _chatItems = <_ChatItem>[];
  List<_ChatSystemAlert> _composerAlerts = <_ChatSystemAlert>[];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;
  bool _inited = false;
  final Set<String> _reportingMessageIds = <String>{};
  final Set<String> _reportedMessageIds = <String>{};

  Map<String, dynamic> _spot = <String, dynamic>{};
  String _spotKey = "";
  int? _userId;
  List<DistanceUserSummary> _memberSummaries = const <DistanceUserSummary>[];
  DistanceUserSummary? _currentUserSummary;
  bool _comparePopupChecked = false;
  DateTime? _lastScamAlertAt;
  bool _roomClosed = false;
  String? _roomClosedReasonCode;
  String? _roomClosedMessage;
  DateTime? _roomClosedAt;
  String get _baseUrl => ConfigService.getBaseUrl();
  static const String _scamWarningText =
      "Warning: A potentially fraudulent message was detected. Do not transfer money or share personal information.";
  static const List<String> _suspiciousPhrases = <String>[
    'โอนเงิน',
    'โอนมา',
    'ส่งเลขบัญชี',
    'เลขบัญชี',
    'พร้อมเพย์',
    'transfer money',
    'send account number',
    'bank account',
    'promptpay',
    'qr code',
    'qr-code',
    'scan qr',
    'scan the qr',
    'scan this qr',
    'scan this qr code',
    'scan this qr-code',
    'help me scan',
    'can u scan',
    'evaluate my running performance',
  ];

  List<Uri> _candidateUris(String path,
      {Map<String, String>? queryParameters}) {
    final primary =
        Uri.parse("$_baseUrl$path").replace(queryParameters: queryParameters);
    final out = <Uri>[primary];

    final fallbackBase = ConfigService.getDevFallbackUri(path);
    if (fallbackBase != null) {
      final fallback = fallbackBase.replace(queryParameters: queryParameters);
      if (!ConfigService.isSameHostPort(primary, fallback)) {
        out.add(fallback);
      }
    }

    return out;
  }

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    // Service integration point: the page still owns polling/state,
    // but message loading now goes through SpotChatService.
    _spotChatService = SpotChatService(baseUrl: _baseUrl);
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  String _chatUnavailableText() {
    final code = Localizations.localeOf(context).languageCode;
    switch (code) {
      case 'th':
        return 'ปิดแชทแล้ว';
      case 'zh':
        return '聊天已关闭。';
      default:
        return 'Chat closed.';
    }
  }

  Future<void> _init() async {
    final args = (ModalRoute.of(context)?.settings.arguments is Map)
        ? Map<String, dynamic>.from(
            ModalRoute.of(context)!.settings.arguments as Map)
        : <String, dynamic>{};
    final spot = (args["spot"] is Map)
        ? Map<String, dynamic>.from(args["spot"] as Map)
        : <String, dynamic>{};

    _spot = spot;
    _spotKey = _buildSpotKey(spot);
    _userId = await SessionService.getCurrentUserId();

    if (ActivityExpiry.isExpiredAfterGrace(_spot)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(_chatUnavailableText()),
            ),
          );
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (_isCompletedForCurrentUser()) {
      _closeChatForCompletedUser();
      return;
    }

    await _refreshChatState();
    await _refreshMemberSummaries(showPopupIfNeeded: true);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshChatState(silent: true),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    _init();
  }

  String _buildSpotKey(Map<String, dynamic> spot) {
    final explicit =
        (spot["spotKey"] ?? spot["spot_key"] ?? "").toString().trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final stableId =
        (spot["backendSpotId"] ?? spot["id"] ?? "").toString().trim();
    if (stableId.isNotEmpty) {
      return 'spot:$stableId';
    }
    final title = (spot["title"] ?? "").toString().trim().toLowerCase();
    final date = (spot["date"] ?? "").toString().trim().toLowerCase();
    final time = (spot["time"] ?? "").toString().trim().toLowerCase();
    final location = (spot["location"] ?? "").toString().trim().toLowerCase();
    return "$title|$date|$time|$location";
  }

  bool _isCompletedForCurrentUser() {
    return (_spot["completed_at"] ?? "").toString().trim().isNotEmpty;
  }

  bool _isRoomClosedForUi() {
    return _roomClosed || ActivityExpiry.isExpiredAfterGrace(_spot);
  }

  void _applyRoomClosedState({
    required bool roomClosed,
    String? reasonCode,
    String? message,
    String? closedAtRaw,
  }) {
    final parsedClosedAt =
        DateTime.tryParse((closedAtRaw ?? '').trim())?.toLocal();
    if (!mounted) return;
    setState(() {
      _roomClosed = roomClosed;
      _roomClosedReasonCode =
          reasonCode?.trim().isEmpty == true ? null : reasonCode?.trim();
      _roomClosedMessage =
          message?.trim().isEmpty == true ? null : message?.trim();
      _roomClosedAt = parsedClosedAt;
    });
  }

  void _closeChatForCompletedUser() {
    _pollTimer?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(_chatUnavailableText()),
        ),
      );
    Navigator.of(context).maybePop();
  }

  int? _spotId() {
    return int.tryParse(
      (_spot["backendSpotId"] ?? _spot["id"] ?? "").toString(),
    );
  }

  String _comparePopupStorageKey() {
    final roomKey = (_spotId()?.toString() ?? _spotKey).trim();
    final userKey = (_userId?.toString() ?? "0").trim();
    return "spot_compare_popup_shown_${roomKey}_$userKey";
  }

  DistanceUserSummary? _findCurrentUserSummary(
    List<DistanceUserSummary> members,
  ) {
    if (_userId == null) return null;
    for (final member in members) {
      if (member.userId == _userId) return member;
    }
    return null;
  }

  bool _isSameMember(
    DistanceUserSummary current,
    DistanceUserSummary other,
  ) {
    if (current.userId > 0 &&
        other.userId > 0 &&
        current.userId == other.userId) {
      return true;
    }

    final currentName = current.displayName.trim().toLowerCase();
    final otherName = other.displayName.trim().toLowerCase();
    final currentImage = current.profileImageUrl.trim().toLowerCase();
    final otherImage = other.profileImageUrl.trim().toLowerCase();

    if (currentName.isNotEmpty &&
        otherName.isNotEmpty &&
        currentName == otherName) {
      if (currentImage.isNotEmpty &&
          otherImage.isNotEmpty &&
          currentImage == otherImage) {
        return true;
      }
      if (current.district.trim().toLowerCase() ==
              other.district.trim().toLowerCase() &&
          current.province.trim().toLowerCase() ==
              other.province.trim().toLowerCase()) {
        return true;
      }
    }

    return false;
  }

  String? _comparisonTextForMember(DistanceUserSummary member) {
    final current = _currentUserSummary;
    if (current == null ||
        _isSameMember(current, member) ||
        current.totalKm == null ||
        member.totalKm == null) {
      return null;
    }
    return compareUserDistance(
      currentUserKm: current.totalKm!,
      otherUserKm: member.totalKm!,
      userName: member.displayName,
      mode: ComparisonTextMode.memberList,
    );
  }

  _ComparisonBand? _comparisonBandForMember(DistanceUserSummary member) {
    final current = _currentUserSummary;
    if (current == null ||
        _isSameMember(current, member) ||
        current.totalKm == null ||
        member.totalKm == null) {
      return null;
    }
    final diff = current.totalKm! - member.totalKm!;
    final absDiff = diff.abs();
    if (absDiff < 0.000001) return _ComparisonBand.tied;
    if (diff > 10) return _ComparisonBand.aheadFar;
    if (diff >= 0) return _ComparisonBand.aheadNear;
    if (absDiff <= 10) return _ComparisonBand.behindNear;
    return _ComparisonBand.behindFar;
  }

  List<_ComparisonEntry> _buildComparisonEntries(
    List<DistanceUserSummary> members,
  ) {
    final current = _findCurrentUserSummary(members);
    if (current == null || current.totalKm == null) {
      return const <_ComparisonEntry>[];
    }

    final entries = members
        .where((member) => !_isSameMember(current, member))
        .where((member) => member.totalKm != null)
        .map((member) {
          final band = _comparisonBandForMember(member);
          if (band == null) return null;
          final diffKm = (current.totalKm! - member.totalKm!).abs();
          return _ComparisonEntry(
            member: member,
            band: band,
            diffKm: diffKm,
            summary: compareUserDistance(
              currentUserKm: current.totalKm!,
              otherUserKm: member.totalKm!,
              userName: member.displayName,
              mode: ComparisonTextMode.memberList,
            ),
            detail: compareUserDistance(
              currentUserKm: current.totalKm!,
              otherUserKm: member.totalKm!,
              userName: member.displayName,
              mode: ComparisonTextMode.popup,
            ),
          );
        })
        .whereType<_ComparisonEntry>()
        .toList();

    entries.sort((a, b) {
      final bandCompare = a.band.index.compareTo(b.band.index);
      if (bandCompare != 0) return bandCompare;
      final diffCompare = b.diffKm.compareTo(a.diffKm);
      if (diffCompare != 0) return diffCompare;
      return a.member.displayName
          .toLowerCase()
          .compareTo(b.member.displayName.toLowerCase());
    });
    return entries;
  }

  String _comparisonBandTitle(_ComparisonBand band) {
    switch (band) {
      case _ComparisonBand.aheadFar:
        return tr('comparison_ahead_far_title');
      case _ComparisonBand.aheadNear:
        return tr('comparison_ahead_near_title');
      case _ComparisonBand.behindNear:
        return tr('comparison_behind_near_title');
      case _ComparisonBand.behindFar:
        return tr('comparison_behind_far_title');
      case _ComparisonBand.tied:
        return tr('comparison_tied_title');
    }
  }

  String _comparisonBandDescription(_ComparisonBand band) {
    switch (band) {
      case _ComparisonBand.aheadFar:
        return tr('comparison_ahead_far_subtitle');
      case _ComparisonBand.aheadNear:
        return tr('comparison_ahead_near_subtitle');
      case _ComparisonBand.behindNear:
        return tr('comparison_behind_near_subtitle');
      case _ComparisonBand.behindFar:
        return tr('comparison_behind_far_subtitle');
      case _ComparisonBand.tied:
        return tr('comparison_tied_subtitle');
    }
  }

  _ComparePopupVisual _comparisonBandVisual(_ComparisonBand band) {
    switch (band) {
      case _ComparisonBand.aheadFar:
        return const _ComparePopupVisual(
          accentColor: Color(0xFFFFD75E),
          cardColor: Color(0xFFFFF4C7),
          iconPanelColor: Color(0xFFFFF0B5),
          chipColor: Color(0xFFD7DCE8),
          assetPath: AppAssets.user_icons_compare_badge,
          badgeLabel: '',
          headline: '',
          supporting: '',
          icon: Icons.emoji_events_rounded,
        );
      case _ComparisonBand.aheadNear:
        return const _ComparePopupVisual(
          accentColor: Color(0xFFFFB300),
          cardColor: Color(0xFFFFF3D6),
          iconPanelColor: Color(0xFFFFE3A3),
          chipColor: Color(0xFFD7DCE8),
          assetPath: AppAssets.user_icons_compare_warning,
          badgeLabel: '',
          headline: '',
          supporting: '',
          icon: Icons.warning_rounded,
        );
      case _ComparisonBand.behindNear:
        return const _ComparePopupVisual(
          accentColor: Color(0xFFFFD75E),
          cardColor: Color(0xFFFFF1CC),
          iconPanelColor: Color(0xFFFFF0C4),
          chipColor: Color(0xFFD7DCE8),
          assetPath: AppAssets.user_icons_compare_bolt,
          badgeLabel: '',
          headline: '',
          supporting: '',
          icon: Icons.flash_on_rounded,
        );
      case _ComparisonBand.behindFar:
        return const _ComparePopupVisual(
          accentColor: Color(0xFFFFC94A),
          cardColor: Color(0xFFFFF1CC),
          iconPanelColor: Color(0xFFFFE7A0),
          chipColor: Color(0xFFD7DCE8),
          assetPath: AppAssets.user_icons_compare_swords,
          badgeLabel: '',
          headline: '',
          supporting: '',
          icon: Icons.emoji_events_rounded,
        );
      case _ComparisonBand.tied:
        return const _ComparePopupVisual(
          accentColor: Color(0xFFFFD75E),
          cardColor: Color(0xFFFFF4C7),
          iconPanelColor: Color(0xFFFFF0B5),
          chipColor: Color(0xFFD7DCE8),
          assetPath: AppAssets.user_icons_compare_equal,
          badgeLabel: '',
          headline: '',
          supporting: '',
          icon: Icons.drag_handle_rounded,
        );
    }
  }

  void _openMemberProfile({
    required BuildContext context,
    required DistanceUserSummary member,
    required bool isCurrentUser,
  }) {
    Navigator.of(context).pop();
    Navigator.of(this.context).pushNamed(
      AppRoutes.userProfile,
      arguments: <String, dynamic>{
        "public": !isCurrentUser,
        "userId": member.userId,
        "displayName": member.displayName,
        "role": member.role.trim().isEmpty ? "user" : member.role.trim(),
        "profileImageUrl": member.profileImageUrl,
        "district": member.district,
        "province": member.province,
        "totalKm": member.totalKm,
        "joinedCount": member.joinedCount,
        "completedCount": member.completedCount,
        "postCount": member.postCount,
        "status": member.status,
      },
    );
  }

  Future<void> _showComparisonInfo(_ComparisonEntry entry) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.member.displayName),
        content: Text(
          "${entry.detail}\n\n${tr('gap_with_value', params: {
                'value': formatDistanceKm(entry.diffKm)
              })}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showComparisonOverview(
    List<DistanceUserSummary> members,
  ) async {
    final entries = _buildComparisonEntries(members);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.82,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('distance_overview'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('distance_overview_subtitle'),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  if (entries.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          tr('no_comparable_members_found'),
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _ComparisonBand.values.map((band) {
                            final bandEntries = entries
                                .where((entry) => entry.band == band)
                                .toList();
                            return _ComparisonSection(
                              assetPath: _comparisonBandVisual(band).assetPath,
                              fallbackIcon: _comparisonBandVisual(band).icon,
                              iconTint: _comparisonBandVisual(band).accentColor,
                              iconBg:
                                  _comparisonBandVisual(band).iconPanelColor,
                              title: _comparisonBandTitle(band),
                              subtitle: _comparisonBandDescription(band),
                              children: bandEntries.isEmpty
                                  ? <Widget>[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: 10,
                                        ),
                                        child: Text(
                                          UserStrings.text('no_data'),
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ]
                                  : bandEntries
                                      .map(
                                        (entry) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: _ComparisonMemberCard(
                                            entry: entry,
                                            onTap: () => _openMemberProfile(
                                              context: context,
                                              member: entry.member,
                                              isCurrentUser: false,
                                            ),
                                            onInfoTap: () =>
                                                _showComparisonInfo(entry),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _ComparePopupVisual _comparePopupVisual({
    required double currentUserKm,
    required double otherUserKm,
  }) {
    final diff = (currentUserKm - otherUserKm).abs();
    if ((currentUserKm - otherUserKm).abs() < 0.000001) {
      return const _ComparePopupVisual(
        accentColor: Color(0xFFFFD75E),
        cardColor: Color(0xFFFFF4C7),
        iconPanelColor: Color(0xFFFFF0B5),
        chipColor: Color(0xFFD7DCE8),
        assetPath: AppAssets.user_icons_compare_equal,
        badgeLabel: "Your Score",
        headline: "Perfect tie",
        supporting: "You matched this runner exactly.",
        icon: Icons.drag_handle_rounded,
      );
    }
    if (currentUserKm > otherUserKm) {
      if (diff <= 10) {
        return const _ComparePopupVisual(
          accentColor: Color(0xFFFFB300),
          cardColor: Color(0xFFFFF3D6),
          iconPanelColor: Color(0xFFFFE3A3),
          chipColor: Color(0xFFD7DCE8),
          assetPath: AppAssets.user_icons_compare_warning,
          badgeLabel: "Your Score",
          headline: "Winning pace",
          supporting: "You are holding a small lead.",
          icon: Icons.warning_rounded,
        );
      }
      return const _ComparePopupVisual(
        accentColor: Color(0xFFFFD75E),
        cardColor: Color(0xFFFFF4C7),
        iconPanelColor: Color(0xFFFFF0B5),
        chipColor: Color(0xFFD7DCE8),
        assetPath: AppAssets.user_icons_compare_badge,
        badgeLabel: "Your Score",
        headline: "You are leading",
        supporting: "A big gap is already on your side.",
        icon: Icons.emoji_events_rounded,
      );
    }
    if (diff < 10) {
      return const _ComparePopupVisual(
        accentColor: Color(0xFFFFD75E),
        cardColor: Color(0xFFFFF1CC),
        iconPanelColor: Color(0xFFFFF0C4),
        chipColor: Color(0xFFD7DCE8),
        assetPath: AppAssets.user_icons_compare_bolt,
        badgeLabel: "Your Score",
        headline: "Almost there",
        supporting: "This race is still very close.",
        icon: Icons.flash_on_rounded,
      );
    }
    return const _ComparePopupVisual(
      accentColor: Color(0xFFFFC94A),
      cardColor: Color(0xFFFFF1CC),
      iconPanelColor: Color(0xFFFFE7A0),
      chipColor: Color(0xFFD7DCE8),
      assetPath: AppAssets.user_icons_compare_swords,
      badgeLabel: "Your Score",
      headline: "Time to push",
      supporting: "You still have distance to recover.",
      icon: Icons.gpp_bad_rounded,
    );
  }

  Widget _comparePopupIcon(_ComparePopupVisual visual) {
    if (visual.assetPath == AppAssets.user_icons_compare_equal) {
      return Container(
        width: 94,
        height: 94,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: visual.iconPanelColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(
          Icons.drag_handle_rounded,
          size: 62,
          color: Colors.black87,
        ),
      );
    }
    if ((visual.assetPath ?? '').isNotEmpty) {
      return Container(
        width: 94,
        height: 94,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: visual.iconPanelColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Image.asset(
          visual.assetPath!,
          width: 76,
          height: 76,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            visual.icon,
            size: 62,
            color: visual.accentColor,
          ),
        ),
      );
    }
    return Container(
      width: 82,
      height: 82,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visual.iconPanelColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(
        visual.icon,
        size: 56,
        color: visual.accentColor,
      ),
    );
  }

  Future<void> _showDistanceComparisonPopup({
    required String message,
    required _ComparePopupVisual visual,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Distance comparison",
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 540,
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  child: Container(
                    width: 540,
                    padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCE1EC),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 32,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD75E),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              visual.badgeLabel,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F9FE),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 122,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    children: [
                                      _comparePopupIcon(visual),
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: visual.chipColor,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: const Text(
                                          "Keep\nmoving",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      18,
                                      18,
                                      18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD9D9D9),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.5),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            visual.headline,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w900,
                                              color: visual.accentColor,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          visual.supporting,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.black,
                                            height: 1.15,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          message,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            height: 1.32,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          "Stay consistent and push your pace in the next run.",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.3,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF9E9E9E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text(
                                "SKIP",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<List<DistanceUserSummary>> _refreshMemberSummaries({
    bool showPopupIfNeeded = false,
  }) async {
    final spotId = _spotId();
    if (spotId == null) return _memberSummaries;

    try {
      final members = await UserDistanceService.fetchSpotMembers(spotId);
      final current = _findCurrentUserSummary(members);
      if (mounted) {
        setState(() {
          _memberSummaries = members;
          _currentUserSummary = current;
        });
      } else {
        _memberSummaries = members;
        _currentUserSummary = current;
      }

      if (showPopupIfNeeded) {
        await _maybeShowComparisonPopup(members);
      }
      return members;
    } catch (e) {
      if (kDebugMode) {
        debugPrint("[SpotChat] member summary fetch failed: $e");
      }
      return _memberSummaries;
    }
  }

  Future<void> _maybeShowComparisonPopup(
    List<DistanceUserSummary> members,
  ) async {
    if (!mounted || _comparePopupChecked || _userId == null) {
      return;
    }
    _comparePopupChecked = true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_comparePopupStorageKey()) == true) {
      return;
    }

    final current = _findCurrentUserSummary(members);
    final entries = _buildComparisonEntries(members);
    if (current?.totalKm == null || entries.isEmpty) {
      return;
    }

    if (!mounted) return;
    await _showComparisonOverview(members);

    await prefs.setBool(_comparePopupStorageKey(), true);
  }

  Future<void> _showMemberList() async {
    try {
      final members = await _refreshMemberSummaries();
      if (!mounted) return;
      await _showComparisonOverview(members);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text("Unable to load participants: $e")),
        );
    }
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (_spotKey.isEmpty) return;

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      Object? lastError;
      List<_ChatMessage>? rows;

      for (final uri in _candidateUris(
        "/api/spot-chat/messages",
        queryParameters: {"spot_key": _spotKey},
      )) {
        try {
          if (kDebugMode) {
            debugPrint("[SpotChat] GET $uri");
          }
          final rawRows = await _spotChatService.fetchMessageRowsFromUri(
            uri,
            headers: {
              "Accept": "application/json",
              if (_userId != null) "x-user-id": _userId.toString(),
            },
          ).timeout(const Duration(seconds: 15));

          rows = rawRows.map((e) => _ChatMessage.fromJson(e)).toList();
          rows = _mergeFetchedMessagesWithOptimistic(rows);
          break;
        } catch (e) {
          lastError = e;
        }
      }

      if (rows == null) {
        throw Exception("$lastError");
      }

      if (!mounted) return;
      setState(() {
        _messages = rows!;
        _rebuildChatItems();
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchRoomAlerts({bool silent = false}) async {
    if (_spotKey.isEmpty) return;

    try {
      Object? lastError;
      List<_ChatSystemAlert>? alerts;

      for (final uri in _candidateUris(
        "/api/spot-chat/room-alerts",
        queryParameters: {"spot_key": _spotKey},
      )) {
        try {
          if (kDebugMode) {
            debugPrint("[SpotChat] GET $uri");
          }
          final res = await http.get(uri, headers: {
            "Accept": "application/json"
          }).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) {
            lastError = Exception("HTTP ${res.statusCode}: ${res.body}");
            continue;
          }

          final decoded = jsonDecode(res.body);
          if (decoded is! List) {
            lastError = Exception("Invalid room alert response format");
            continue;
          }

          alerts = decoded
              .whereType<Map>()
              .map((e) =>
                  _ChatSystemAlert.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          break;
        } catch (e) {
          lastError = e;
        }
      }

      if (alerts == null) {
        if (!silent && kDebugMode) {
          debugPrint("[SpotChat] room alert fetch failed: $lastError");
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _mergeSystemAlerts(alerts!);
        _rebuildChatItems();
      });
    } catch (e) {
      if (!silent && kDebugMode) {
        debugPrint("[SpotChat] room alert fetch exception: $e");
      }
    }
  }

  Future<void> _fetchRoomStatus({bool silent = false}) async {
    if (_spotKey.isEmpty) return;

    try {
      Object? lastError;
      Map<String, dynamic>? payload;

      for (final uri in _candidateUris(
        "/api/spot-chat/room-status",
        queryParameters: {
          "spot_key": _spotKey,
          if (_userId != null) "user_id": _userId.toString(),
        },
      )) {
        try {
          if (kDebugMode) {
            debugPrint("[SpotChat] GET $uri");
          }
          final res = await http.get(uri, headers: {
            "Accept": "application/json",
            if (_userId != null) "x-user-id": _userId.toString(),
          }).timeout(const Duration(seconds: 15));

          if (res.statusCode != 200) {
            lastError = Exception("HTTP ${res.statusCode}: ${res.body}");
            continue;
          }

          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
            break;
          }
          lastError = Exception("Invalid room status response format");
        } catch (e) {
          lastError = e;
        }
      }

      if (payload == null) {
        if (!silent && kDebugMode) {
          debugPrint("[SpotChat] room status fetch failed: $lastError");
        }
        return;
      }

      _applyRoomClosedState(
        roomClosed: payload["room_closed"] == true,
        reasonCode: (payload["reason_code"] ?? "").toString(),
        message: (payload["user_message"] ?? "").toString(),
        closedAtRaw: (payload["closed_at"] ?? "").toString(),
      );
    } catch (e) {
      if (!silent && kDebugMode) {
        debugPrint("[SpotChat] room status fetch exception: $e");
      }
    }
  }

  Future<void> _refreshChatState({bool silent = false}) async {
    if (_isCompletedForCurrentUser()) {
      _closeChatForCompletedUser();
      return;
    }
    await _fetchRoomStatus(silent: true);
    await _fetchMessages(silent: silent);
    await _fetchRoomAlerts(silent: true);
  }

  Future<Map<String, dynamic>?> _moderateBeforeSend(String message) async {
    Object? lastError;

    for (final uri in _candidateUris("/api/moderate/chat-message")) {
      try {
        if (kDebugMode) {
          debugPrint("[SpotChat] MODERATE $uri");
        }
        final res = await http
            .post(
              uri,
              headers: {
                "Content-Type": "application/json",
                if (_userId != null) "x-user-id": _userId.toString(),
              },
              body: jsonEncode({"text": message}),
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode != 200) {
          lastError = Exception("HTTP ${res.statusCode}: ${res.body}");
          continue;
        }

        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        lastError = Exception("Invalid moderation response format");
      } catch (e) {
        lastError = e;
      }
    }

    if (kDebugMode && lastError != null) {
      debugPrint("[SpotChat] moderation preflight failed: $lastError");
    }
    return null;
  }

  String _buildModerationDialogMessage(
    Map<String, dynamic> moderationResult,
    String fallback,
  ) {
    final userMessage =
        (moderationResult["userMessage"] ?? "").toString().trim();
    final reasons = moderationResult["reasons"] is List
        ? List<String>.from(
            (moderationResult["reasons"] as List)
                .map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty),
          )
        : const <String>[];

    if (reasons.isEmpty) {
      return userMessage.isNotEmpty ? userMessage : fallback;
    }

    final preview = reasons.take(3).join(", ");
    final base = userMessage.isNotEmpty ? userMessage : fallback;
    return "$base\n\nSignals: $preview";
  }

  Future<bool> _runModerationPreflight(String message) async {
    final moderationResult = await _moderateBeforeSend(message);
    if (moderationResult == null) {
      return true;
    }

    final action = (moderationResult["action"] ?? "allow").toString();
    if (action == "allow") {
      return true;
    }

    if (action == "block") {
      await _showBlockedModerationDialog(
        _buildModerationDialogMessage(
          moderationResult,
          "Your message was blocked by moderation policy.",
        ),
      );
      return false;
    }

    if (action == "warn" || action == "review") {
      return true;
    }

    return true;
  }

  Future<void> _send() async {
    final msg = _textCtrl.text.trim();
    if (msg.isEmpty || _sending) return;
    if (_isCompletedForCurrentUser()) {
      _closeChatForCompletedUser();
      return;
    }
    if (_isRoomClosedForUi()) {
      _showSnack(_roomClosedMessage ?? _chatUnavailableText());
      return;
    }
    if (_userId == null || _userId! <= 0) {
      _showSnack("No active user session.");
      return;
    }

    setState(() => _sending = true);
    try {
      final shouldSend = await _runModerationPreflight(msg);
      if (!shouldSend) {
        return;
      }

      // Optimistic phishing UI integration:
      // if the outgoing message contains a URL, we immediately show it in the
      // list with phishingScanStatus=scanning until the backend poll replaces it.
      final optimisticClientKey = _messageContainsUrl(msg)
          ? _insertOptimisticScanningMessage(msg)
          : null;

      Object? lastError;
      bool sent = false;
      bool handledScamBlock = false;

      for (final uri in _candidateUris("/api/spot-chat/messages")) {
        try {
          if (kDebugMode) {
            debugPrint("[SpotChat] POST $uri");
          }
          final res = await http
              .post(
                uri,
                headers: {
                  "Content-Type": "application/json",
                  "x-user-id": _userId.toString(),
                },
                body: jsonEncode({
                  "spot_key": _spotKey,
                  "user_id": _userId,
                  "message": msg,
                  if (optimisticClientKey != null)
                    "client_message_key": optimisticClientKey,
                }),
              )
              .timeout(const Duration(seconds: 15));

          final body = res.body.trim();
          final decoded = body.isEmpty ? null : jsonDecode(body);
          final payload =
              decoded is Map ? Map<String, dynamic>.from(decoded as Map) : null;

          if (res.statusCode == 403 && payload != null) {
            final moderation = payload["moderation"] is Map
                ? Map<String, dynamic>.from(payload["moderation"] as Map)
                : const <String, dynamic>{};
            final moderationTriggered = payload["moderation_triggered"] == true;
            final roomAlertRequired = payload["room_alert_required"] == true ||
                moderation["room_alert_required"] == true;
            final reasonCode = (payload["reason_code"] ?? "").toString();

            if (!moderationTriggered) {
              if (reasonCode == "event_ended" || reasonCode == "chat_closed") {
                _applyRoomClosedState(
                  roomClosed: true,
                  reasonCode: reasonCode,
                  message: (payload["user_message"] ?? payload["message"] ?? "")
                      .toString(),
                  closedAtRaw: (payload["closed_at"] ?? "").toString(),
                );
              }
              _showSnack(
                (payload["user_message"] ??
                        payload["message"] ??
                        "Request was rejected.")
                    .toString(),
              );
              handledScamBlock = true;
              break;
            }

            if (roomAlertRequired || reasonCode == "scam_risk") {
              handledScamBlock = true;
              _appendScamRoomAlert(
                payload["room_alert"] is Map
                    ? Map<String, dynamic>.from(payload["room_alert"] as Map)
                    : null,
              );
              _showSnack(
                (payload["user_message"] ??
                        "Message blocked due to suspicious scam-like content.")
                    .toString(),
              );
              await _showBlockedModerationDialog(
                (payload["user_message"] ??
                        "Your message was blocked because it contains inappropriate or harmful language.")
                    .toString(),
              );
              break;
            }

            await _showBlockedModerationDialog(
              (payload["user_message"] ??
                      "Your message was blocked because it contains inappropriate or harmful language.")
                  .toString(),
            );
            handledScamBlock = true;
            break;
          }

          if (res.statusCode != 201) {
            lastError = Exception("HTTP ${res.statusCode}: ${res.body}");
            continue;
          }

          if (payload?["moderation_triggered"] == true) {
            _showSnack(
              (payload?["user_message"] ??
                      "You used inappropriate language. Please be respectful.")
                  .toString(),
            );
          }
          sent = true;
          break;
        } catch (e) {
          lastError = e;
        }
      }

      if (handledScamBlock) {
        if (optimisticClientKey != null) {
          _removeOptimisticMessage(optimisticClientKey);
        }
        _textCtrl.clear();
        return;
      }

      if (!sent) {
        if (optimisticClientKey != null) {
          _removeOptimisticMessage(optimisticClientKey);
        }
        throw Exception("$lastError");
      }

      _textCtrl.clear();
      await _fetchMessages(silent: true);
    } catch (e) {
      // If send fails, remove the temporary scanning bubble.
      final hasUrl = _messageContainsUrl(msg);
      if (hasUrl) {
        _removeOptimisticMessageByText(msg);
      }
      _showSnack("Send failed: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _messageContainsUrl(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    final urlPattern = RegExp(
      r'((https?:\/\/)|(www\.))[^\s]+',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(normalized);
  }

  String _insertOptimisticScanningMessage(String text) {
    final now = DateTime.now();
    // client_message_key integration:
    // generate a stable-enough demo key so the backend can return it and the
    // next polling cycle can replace the optimistic message reliably.
    final clientKey = _generateClientMessageKey();
    final optimisticMessage = _ChatMessage.optimisticScanning(
      clientMessageKey: clientKey,
      userId: _userId ?? 0,
      senderName: 'You',
      text: text,
      createdAt: now,
    );

    setState(() {
      _messages = <_ChatMessage>[..._messages, optimisticMessage];
      _rebuildChatItems();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });

    return clientKey;
  }

  String _generateClientMessageKey() {
    final userPart = _userId?.toString() ?? 'guest';
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'cmk-$userPart-$now';
  }

  void _removeOptimisticMessage(String clientMessageKey) {
    if (!mounted) return;
    setState(() {
      _messages = _messages
          .where(
            (message) => !(message.isOptimistic &&
                message.clientMessageKey == clientMessageKey),
          )
          .toList();
      _rebuildChatItems();
    });
  }

  void _removeOptimisticMessageByText(String text) {
    if (!mounted) return;
    setState(() {
      _messages = _messages
          .where(
            (message) => !(message.isOptimistic &&
                message.userId == _userId &&
                message.text == text),
          )
          .toList();
      _rebuildChatItems();
    });
  }

  List<_ChatMessage> _mergeFetchedMessagesWithOptimistic(
    List<_ChatMessage> fetchedMessages,
  ) {
    final optimisticMessages =
        _messages.where((message) => message.isOptimistic).toList();
    if (optimisticMessages.isEmpty) {
      return fetchedMessages;
    }

    final merged = <_ChatMessage>[...fetchedMessages];
    for (final optimistic in optimisticMessages) {
      final replaced = fetchedMessages.any(
        (serverMessage) => _matchesOptimisticMessage(
          optimistic,
          serverMessage,
        ),
      );
      if (!replaced) {
        merged.add(optimistic);
      }
    }

    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  bool _matchesOptimisticMessage(
    _ChatMessage optimistic,
    _ChatMessage serverMessage,
  ) {
    // Prefer matching by client_message_key when available.
    final optimisticKey = (optimistic.clientMessageKey ?? '').trim();
    final serverKey = (serverMessage.clientMessageKey ?? '').trim();
    if (optimisticKey.isNotEmpty &&
        serverKey.isNotEmpty &&
        optimisticKey == serverKey) {
      return true;
    }

    if (optimistic.userId != serverMessage.userId) {
      return false;
    }
    if (optimistic.text.trim() != serverMessage.text.trim()) {
      return false;
    }

    final seconds = optimistic.createdAt
        .difference(serverMessage.createdAt)
        .inSeconds
        .abs();
    return seconds <= 30;
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showBlockedModerationDialog(String text) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Message Blocked"),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _promptReportMessage(_ChatMessage message) async {
    final messageId = message.id;
    if (messageId.isEmpty ||
        _reportingMessageIds.contains(messageId) ||
        _reportedMessageIds.contains(messageId)) {
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Report user"),
            content: const Text(
              "Do you want to report this user?\n\nThis message may contain inappropriate language.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Report user"),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted || _userId == null) return;

    setState(() => _reportingMessageIds.add(messageId));
    try {
      Object? lastError;
      bool submitted = false;
      for (final uri in _candidateUris("/api/spot-chat/report-user")) {
        try {
          final res = await http
              .post(
                uri,
                headers: {
                  "Content-Type": "application/json",
                  "x-user-id": _userId.toString(),
                },
                body: jsonEncode({
                  "reported_user_id": message.userId,
                  "spot_key": _spotKey,
                  "message_id": message.id,
                  "reason_code": "INAPPROPRIATE_LANGUAGE",
                }),
              )
              .timeout(const Duration(seconds: 15));
          if (res.statusCode != 201) {
            lastError = Exception("HTTP ${res.statusCode}: ${res.body}");
            continue;
          }
          submitted = true;
          break;
        } catch (e) {
          lastError = e;
        }
      }

      if (!submitted) {
        throw Exception("$lastError");
      }

      if (!mounted) return;
      setState(() => _reportedMessageIds.add(messageId));
      _showSnack("Report submitted. Thank you.");
    } catch (e) {
      _showSnack("Report failed: $e");
    } finally {
      if (mounted) {
        setState(() => _reportingMessageIds.remove(messageId));
      }
    }
  }

  void _appendScamRoomAlert([Map<String, dynamic>? roomAlertPayload]) {
    final now = DateTime.now();
    final recent = _lastScamAlertAt != null &&
        now.difference(_lastScamAlertAt!) < const Duration(seconds: 20);
    final alert = roomAlertPayload == null
        ? _ChatSystemAlert(
            id: 'scam-alert-${now.millisecondsSinceEpoch}',
            alertType: 'scam_warning',
            text: _scamWarningText,
            createdAt: now,
          )
        : _ChatSystemAlert.fromJson(roomAlertPayload);
    if (recent && _systemAlerts.any((existing) => existing.id == alert.id)) {
      return;
    }

    setState(() {
      _lastScamAlertAt = now;
      _mergeSystemAlerts([alert]);
      _rebuildChatItems();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  void _mergeSystemAlerts(List<_ChatSystemAlert> incoming) {
    final byId = <String, _ChatSystemAlert>{
      for (final alert in _systemAlerts) _systemAlertStoreKey(alert): alert,
    };
    for (final alert in incoming) {
      byId[_systemAlertStoreKey(alert)] = alert;
    }
    _systemAlerts
      ..clear()
      ..addAll(byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  void _rebuildChatItems() {
    final items = <_ChatItem>[];
    final messagesById = <String, _ChatMessage>{
      for (final message in _messages)
        if (message.id.isNotEmpty) message.id: message,
    };
    final messagesByClientKey = <String, _ChatMessage>{
      for (final message in _messages)
        if ((message.clientMessageKey ?? '').isNotEmpty)
          message.clientMessageKey!: message,
    };
    final warningsByMessageId = <String, List<_ChatSystemAlert>>{};
    final collectedWarningKeys = <String>{};
    final renderedWarningKeys = <String>{};
    final unanchoredWarnings = <_ChatSystemAlert>[];
    final unanchoredWarningKeys = <String>{};

    for (final alert in _systemAlerts) {
      // Anchor resolution is strict: use an explicit server message id first,
      // then a client correlation key that can map a local optimistic message
      // to its eventual server-backed message id.
      final anchorMessageId = _resolveAnchorMessageId(
        alert,
        messagesById: messagesById,
        messagesByClientKey: messagesByClientKey,
      );
      final inferredAnchorMessageId =
          (anchorMessageId == null || anchorMessageId.isEmpty)
              ? _inferAnchorMessageId(alert)
              : anchorMessageId;
      if (inferredAnchorMessageId == null || inferredAnchorMessageId.isEmpty) {
        final unanchoredKey = _warningDedupKey(alert);
        if (unanchoredWarningKeys.add(unanchoredKey)) {
          unanchoredWarnings.add(alert);
        }
        continue;
      }
      final normalizedAlert =
          alert.copyWith(anchorMessageId: inferredAnchorMessageId);
      final warningKey = _warningDedupKey(normalizedAlert);
      if (collectedWarningKeys.add(warningKey)) {
        warningsByMessageId
            .putIfAbsent(
              inferredAnchorMessageId,
              () => <_ChatSystemAlert>[],
            )
            .add(normalizedAlert);
      }
    }

    for (final alerts in warningsByMessageId.values) {
      alerts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    for (final message in _messages) {
      items.add(_ChatItem.message(message));

      final warnings = _buildWarningsForMessage(
        message,
        roomAlerts:
            warningsByMessageId[message.id] ?? const <_ChatSystemAlert>[],
      );
      for (final warning in warnings) {
        final warningKey = _warningDedupKey(warning);
        if (renderedWarningKeys.add(warningKey)) {
          items.add(_ChatItem.warning(warning));
        }
      }
    }

    _chatItems = items;
    _composerAlerts = unanchoredWarnings
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<_ChatSystemAlert> _buildWarningsForMessage(
    _ChatMessage message, {
    List<_ChatSystemAlert> roomAlerts = const <_ChatSystemAlert>[],
  }) {
    final warnings = <_ChatSystemAlert>[];

    if (roomAlerts.isNotEmpty) {
      warnings.addAll(roomAlerts);
    }
    if (!_hasStableAnchor(message)) {
      return warnings;
    }

    if (_hasInlineVisibleWarning(message)) {
      warnings.add(_ChatSystemAlert(
        id: _inlineWarningId('visible-warning', message),
        alertType: 'inline_warning',
        text: message.visibleWarning,
        createdAt: message.createdAt,
        anchorMessageId: message.id,
        anchorClientMessageKey: message.clientMessageKey,
      ));
    }

    if (_isSuspiciousMessageText(message.text)) {
      warnings.add(_ChatSystemAlert(
        id: _inlineWarningId('local-warning', message),
        alertType: 'scam_warning',
        text: _scamWarningText,
        createdAt: message.createdAt,
        anchorMessageId: message.id,
        anchorClientMessageKey: message.clientMessageKey,
      ));
    }

    warnings.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return warnings;
  }

  String? _resolveAnchorMessageId(
    _ChatSystemAlert alert, {
    required Map<String, _ChatMessage> messagesById,
    required Map<String, _ChatMessage> messagesByClientKey,
  }) {
    final explicitAnchor = (alert.anchorMessageId ?? '').trim();
    if (explicitAnchor.isNotEmpty && messagesById.containsKey(explicitAnchor)) {
      return explicitAnchor;
    }

    final clientAnchor = (alert.anchorClientMessageKey ?? '').trim();
    if (clientAnchor.isNotEmpty) {
      final matchedMessage = messagesByClientKey[clientAnchor];
      if (matchedMessage != null && matchedMessage.id.isNotEmpty) {
        return matchedMessage.id;
      }
    }

    return null;
  }

  String? _inferAnchorMessageId(_ChatSystemAlert alert) {
    if (_messages.isEmpty) return null;

    final candidates = _messages.where((message) {
      final diff = alert.createdAt.difference(message.createdAt);
      return diff.inSeconds >= -5 && diff.inMinutes <= 5;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (candidates.isEmpty) {
      return null;
    }

    for (final message in candidates.reversed) {
      if (_isSuspiciousMessageText(message.text) ||
          _hasInlineVisibleWarning(message)) {
        return message.id.isNotEmpty ? message.id : null;
      }
    }

    for (final message in candidates.reversed) {
      if (_userId != null &&
          message.userId == _userId &&
          message.id.isNotEmpty) {
        return message.id;
      }
    }

    final latest = candidates.last;
    return latest.id.isNotEmpty ? latest.id : null;
  }

  bool _isSuspiciousMessageText(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final collapsed = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    for (final phrase in _suspiciousPhrases) {
      final normalizedPhrase = phrase.toLowerCase();
      final collapsedPhrase =
          normalizedPhrase.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (normalized.contains(normalizedPhrase) ||
          (collapsedPhrase.isNotEmpty && collapsed.contains(collapsedPhrase))) {
        return true;
      }
    }
    final hasQr = collapsed.contains('qr');
    final hasScan = collapsed.contains('scan');
    final hasPerformance =
        collapsed.contains('performance') || collapsed.contains('evaluate');
    if (hasQr && (hasScan || hasPerformance)) {
      return true;
    }
    return false;
  }

  bool _hasStableAnchor(_ChatMessage message) {
    return message.id.isNotEmpty ||
        (message.clientMessageKey ?? '').trim().isNotEmpty;
  }

  bool _hasInlineVisibleWarning(_ChatMessage message) {
    return message.flaggedVisible && message.visibleWarning.isNotEmpty;
  }

  String _inlineWarningId(String prefix, _ChatMessage message) {
    final stableKey = message.id.isNotEmpty
        ? message.id
        : (message.clientMessageKey ?? '').trim();
    return '$prefix-$stableKey';
  }

  String _warningDedupKey(_ChatSystemAlert alert) {
    final anchorId = (alert.anchorMessageId ?? '').trim();
    if (anchorId.isNotEmpty) {
      final alertId = alert.id.trim();
      if (alertId.isNotEmpty) {
        return 'anchor:$anchorId:alert:$alertId';
      }
      return 'anchor:$anchorId:text:${alert.text.trim()}';
    }

    final clientKey = (alert.anchorClientMessageKey ?? '').trim();
    if (clientKey.isNotEmpty) {
      final alertId = alert.id.trim();
      if (alertId.isNotEmpty) {
        return 'client:$clientKey:alert:$alertId';
      }
      return 'client:$clientKey:text:${alert.text.trim()}';
    }

    final alertId = alert.id.trim();
    if (alertId.isNotEmpty) {
      return 'alert:$alertId';
    }

    return 'fallback:${alert.createdAt.toIso8601String()}:${alert.text}';
  }

  String _systemAlertStoreKey(_ChatSystemAlert alert) {
    final alertId = alert.id.trim();
    if (alertId.isNotEmpty) {
      return 'alert:$alertId';
    }
    return _warningDedupKey(alert);
  }

  _ChatMessage? _findMessageById(String? messageId) {
    if (messageId == null || messageId.isEmpty) {
      return null;
    }
    for (final message in _messages) {
      if (message.id == messageId) {
        return message;
      }
    }
    return null;
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _pollTimer?.cancel();
    _spotChatService.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments is Map)
        ? Map<String, dynamic>.from(
            ModalRoute.of(context)!.settings.arguments as Map)
        : <String, dynamic>{};
    final spot = (args["spot"] is Map)
        ? Map<String, dynamic>.from(args["spot"] as Map)
        : <String, dynamic>{};
    final title = (spot["title"] ?? "Spot Group").toString();
    final latestComposerAlert =
        _composerAlerts.isEmpty ? null : _composerAlerts.last;
    final listItemCount =
        _chatItems.length + (latestComposerAlert != null ? 1 : 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Text("$title Chat"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _showMemberList,
            icon: const Icon(Icons.group_outlined),
            tooltip: "Participants",
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text("Load failed\n$_error",
                            textAlign: TextAlign.center))
                    : _chatItems.isEmpty && latestComposerAlert == null
                        ? const Center(child: Text("No messages yet"))
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(12),
                            itemCount: listItemCount,
                            itemBuilder: (context, index) {
                              if (latestComposerAlert != null &&
                                  index == _chatItems.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _buildSystemWarningCard(
                                    latestComposerAlert,
                                  ),
                                );
                              }

                              final item = _chatItems[index];
                              if (item.type == ChatItemType.message) {
                                final message = item.message!;
                                final isMine = _userId != null &&
                                    message.userId == _userId;

                                return Align(
                                  alignment: isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    constraints:
                                        const BoxConstraints(maxWidth: 320),
                                    child: Column(
                                      crossAxisAlignment: isMine
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (!isMine) ...[
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                              bottom: 2,
                                            ),
                                            child: Text(
                                              message.senderName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 11.5,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ],
                                        // Phishing-aware message UI is integrated here.
                                        ChatMessageBubble(
                                          message: message.uiMessage,
                                          isMe: isMine,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final alert = item.warning!;
                              final anchorMessage =
                                  _findMessageById(alert.anchorMessageId);
                              final canReport = anchorMessage != null &&
                                  _userId != null &&
                                  anchorMessage.userId != _userId;
                              final isReporting = anchorMessage != null &&
                                  _reportingMessageIds
                                      .contains(anchorMessage.id);
                              final alreadyReported = anchorMessage != null &&
                                  _reportedMessageIds
                                      .contains(anchorMessage.id);

                              return Center(
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  constraints:
                                      const BoxConstraints(maxWidth: 340),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFFFCC80),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(
                                          Icons.warning_amber_rounded,
                                          color: Color(0xFFE65100),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "System Warning",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFFE65100),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              alert.text,
                                              style: const TextStyle(
                                                color: Color(0xFF6D4C41),
                                              ),
                                            ),
                                            if (canReport) ...[
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton(
                                                  onPressed: isReporting ||
                                                          alreadyReported
                                                      ? null
                                                      : () =>
                                                          _promptReportMessage(
                                                            anchorMessage!,
                                                          ),
                                                  child: Text(
                                                    alreadyReported
                                                        ? "Reported"
                                                        : "Report user",
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isRoomClosedForUi()) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Chat closed",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _roomClosedMessage ?? _chatUnavailableText(),
                            style: const TextStyle(color: Color(0xFF6D4C41)),
                          ),
                          if (_roomClosedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              "Closed at: ${_roomClosedAt!.toLocal()}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6D4C41),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !_isRoomClosedForUi(),
                          decoration: InputDecoration(
                            hintText: _isRoomClosedForUi()
                                ? (_roomClosedMessage ?? _chatUnavailableText())
                                : "Type a message...",
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed:
                              _sending || _isRoomClosedForUi() ? null : _send,
                          child: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text("Send"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemWarningCard(_ChatSystemAlert alert) {
    final anchorMessage = _findMessageById(alert.anchorMessageId);
    final canReport = anchorMessage != null &&
        _userId != null &&
        anchorMessage.userId != _userId;
    final isReporting = anchorMessage != null &&
        _reportingMessageIds.contains(anchorMessage.id);
    final alreadyReported =
        anchorMessage != null && _reportedMessageIds.contains(anchorMessage.id);
    final isSpotUpdateNotice = alert.alertType == 'spot_update_notice';
    final cardColor =
        isSpotUpdateNotice ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final borderColor =
        isSpotUpdateNotice ? const Color(0xFFA5D6A7) : const Color(0xFFFFCC80);
    final accentColor =
        isSpotUpdateNotice ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
    final bodyColor =
        isSpotUpdateNotice ? const Color(0xFF1B5E20) : const Color(0xFF6D4C41);
    final titleText = isSpotUpdateNotice ? "System Update" : "System Warning";
    final leadingIcon =
        isSpotUpdateNotice ? Icons.check_circle : Icons.warning_amber_rounded;

    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                leadingIcon,
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert.text,
                    style: TextStyle(
                      color: bodyColor,
                    ),
                  ),
                  if (canReport) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: isReporting || alreadyReported
                            ? null
                            : () => _promptReportMessage(anchorMessage!),
                        child: Text(
                          alreadyReported ? "Reported" : "Report user",
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatSystemAlert {
  final String id;
  final String alertType;
  final String text;
  final DateTime createdAt;
  final String? anchorMessageId;
  final String? anchorClientMessageKey;

  const _ChatSystemAlert({
    required this.id,
    required this.alertType,
    required this.text,
    required this.createdAt,
    this.anchorMessageId,
    this.anchorClientMessageKey,
  });

  factory _ChatSystemAlert.fromJson(Map<String, dynamic> json) {
    final createdAt =
        DateTime.tryParse((json["created_at"] ?? "").toString())?.toLocal() ??
            DateTime.now();
    return _ChatSystemAlert(
      id: (json["id"] ?? "alert-${createdAt.millisecondsSinceEpoch}")
          .toString(),
      alertType: (json["alert_type"] ?? "").toString().trim(),
      text: (json["message"] ?? _SpotChatGroupPageState._scamWarningText)
          .toString(),
      createdAt: createdAt,
      anchorMessageId: _parseAnchorMessageId(json),
      anchorClientMessageKey: _parseAnchorClientMessageKey(json),
    );
  }

  _ChatSystemAlert copyWith({
    String? id,
    String? alertType,
    String? text,
    DateTime? createdAt,
    String? anchorMessageId,
    String? anchorClientMessageKey,
  }) {
    return _ChatSystemAlert(
      id: id ?? this.id,
      alertType: alertType ?? this.alertType,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      anchorMessageId: anchorMessageId ?? this.anchorMessageId,
      anchorClientMessageKey:
          anchorClientMessageKey ?? this.anchorClientMessageKey,
    );
  }

  static String? _parseAnchorMessageId(Map<String, dynamic> json) {
    const candidateKeys = <String>[
      'message_id',
      'flagged_message_id',
      'source_message_id',
      'trigger_message_id',
      'spot_chat_message_id',
    ];
    for (final key in candidateKeys) {
      final value = (json[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String? _parseAnchorClientMessageKey(Map<String, dynamic> json) {
    const candidateKeys = <String>[
      'clientMessageKey',
      'clientMessageId',
      'client_message_id',
      'client_message_key',
      'requestId',
      'request_id',
      'tempMessageId',
      'temp_message_id',
    ];
    for (final key in candidateKeys) {
      final value = (json[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class _ComparePopupVisual {
  final Color accentColor;
  final Color cardColor;
  final Color iconPanelColor;
  final Color chipColor;
  final String? assetPath;
  final String badgeLabel;
  final String headline;
  final String supporting;
  final IconData icon;
  final bool useCupAsset;

  const _ComparePopupVisual({
    required this.accentColor,
    required this.cardColor,
    required this.iconPanelColor,
    required this.chipColor,
    this.assetPath,
    required this.badgeLabel,
    required this.headline,
    required this.supporting,
    required this.icon,
    this.useCupAsset = false,
  });
}

enum _ComparisonBand { aheadFar, aheadNear, behindNear, behindFar, tied }

class _ComparisonEntry {
  final DistanceUserSummary member;
  final _ComparisonBand band;
  final double diffKm;
  final String summary;
  final String detail;

  const _ComparisonEntry({
    required this.member,
    required this.band,
    required this.diffKm,
    required this.summary,
    required this.detail,
  });
}

class _ComparisonSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? assetPath;
  final IconData fallbackIcon;
  final Color iconTint;
  final Color iconBg;
  final List<Widget> children;

  const _ComparisonSection({
    required this.title,
    required this.subtitle,
    this.assetPath,
    required this.fallbackIcon,
    required this.iconTint,
    required this.iconBg,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isEqualVisual = assetPath == AppAssets.user_icons_compare_equal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: isEqualVisual
                    ? const Icon(
                        Icons.drag_handle_rounded,
                        size: 22,
                        color: Colors.black87,
                      )
                    : (assetPath ?? '').isNotEmpty
                        ? Image.asset(
                            assetPath!,
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              fallbackIcon,
                              size: 22,
                              color: iconTint,
                            ),
                          )
                        : Icon(
                            fallbackIcon,
                            size: 22,
                            color: iconTint,
                          ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _ComparisonMemberCard extends StatelessWidget {
  final _ComparisonEntry entry;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _ComparisonMemberCard({
    required this.entry,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final safeName = entry.member.displayName.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFDDE6FF),
                child: Text(
                  safeName.isNotEmpty
                      ? safeName.substring(0, 1).toUpperCase()
                      : "?",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.member.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.summary,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onInfoTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD0D7E2)),
                    color: const Color(0xFFF8FAFF),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ChatItemType { message, warning }

class _ChatItem {
  final ChatItemType type;
  final _ChatMessage? message;
  final _ChatSystemAlert? warning;

  const _ChatItem._({
    required this.type,
    this.message,
    this.warning,
  });

  factory _ChatItem.message(_ChatMessage message) {
    return _ChatItem._(type: ChatItemType.message, message: message);
  }

  factory _ChatItem.warning(_ChatSystemAlert warning) {
    return _ChatItem._(type: ChatItemType.warning, warning: warning);
  }
}

class _ChatMessage {
  final String id;
  final String? clientMessageKey;
  final int userId;
  final String senderName;
  final String text;
  final DateTime createdAt;
  final bool flaggedVisible;
  final String visibleWarning;
  final ChatMessageModel uiMessage;
  final bool isOptimistic;

  const _ChatMessage({
    required this.id,
    this.clientMessageKey,
    required this.userId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    required this.flaggedVisible,
    required this.visibleWarning,
    required this.uiMessage,
    this.isOptimistic = false,
  });

  factory _ChatMessage.optimisticScanning({
    required String clientMessageKey,
    required int userId,
    required String senderName,
    required String text,
    required DateTime createdAt,
  }) {
    return _ChatMessage(
      id: '',
      clientMessageKey: clientMessageKey,
      userId: userId,
      senderName: senderName,
      text: text,
      createdAt: createdAt,
      flaggedVisible: false,
      visibleWarning: '',
      isOptimistic: true,
      uiMessage: ChatMessageModel(
        id: '',
        clientMessageKey: clientMessageKey,
        userId: userId.toString(),
        body: text,
        createdAt: createdAt,
        containsUrl: true,
        moderationStatus: ModerationStatus.visible,
        riskLevel: RiskLevel.safe,
        phishingScanStatus: PhishingScanStatus.scanning,
        phishingScanReason: null,
      ),
    );
  }

  factory _ChatMessage.fromJson(Map<String, dynamic> json) {
    final uiMessage = ChatMessageModel.fromJson({
      ...json,
      if (!json.containsKey('body') && json.containsKey('message'))
        'body': json['message'],
      if (!json.containsKey('user_id') && json.containsKey('userId'))
        'user_id': json['userId'],
      if (!json.containsKey('created_at') && json.containsKey('createdAt'))
        'created_at': json['createdAt'],
    });
    final createdAt = uiMessage.createdAt;

    return _ChatMessage(
      id: (json['id'] ?? '').toString(),
      clientMessageKey: _parseClientMessageKey(json),
      userId: int.tryParse(
            '${json['user_id'] ?? json['userId'] ?? 0}',
          ) ??
          0,
      senderName:
          (json['sender_name'] ?? json['senderName'] ?? 'User').toString(),
      text: uiMessage.body,
      createdAt: createdAt,
      flaggedVisible:
          json['flagged_visible'] == true || json['flaggedVisible'] == true,
      visibleWarning: (json['visible_warning'] ?? json['visibleWarning'] ?? '')
          .toString()
          .trim(),
      uiMessage: ChatMessageModel(
        id: uiMessage.id.isNotEmpty
            ? uiMessage.id
            : (json['id'] ?? '').toString(),
        clientMessageKey: (uiMessage.clientMessageKey != null &&
                uiMessage.clientMessageKey!.isNotEmpty)
            ? uiMessage.clientMessageKey
            : _parseClientMessageKey(json),
        userId: uiMessage.userId.isNotEmpty
            ? uiMessage.userId
            : (json['user_id'] ?? json['userId'] ?? '').toString(),
        body: uiMessage.body,
        createdAt: uiMessage.createdAt,
        containsUrl: uiMessage.containsUrl,
        moderationStatus: uiMessage.moderationStatus,
        riskLevel: uiMessage.riskLevel,
        phishingScanStatus: uiMessage.phishingScanStatus,
        phishingScanReason: uiMessage.phishingScanReason,
      ),
      isOptimistic: false,
    );
  }

  static String? _parseClientMessageKey(Map<String, dynamic> json) {
    const candidateKeys = <String>[
      'client_message_id',
      'client_message_key',
      'request_id',
      'temp_message_id',
    ];
    for (final key in candidateKeys) {
      final value = (json[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}
