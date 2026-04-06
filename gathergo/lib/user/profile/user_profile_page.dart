import 'package:flutter/material.dart';

import '../../core/services/config_service.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../services/activity_stats_refresh_service.dart';
import 'distance_compare.dart';
import 'user_distance_service.dart';
import 'user_profile_model.dart';
import 'user_profile_service.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loading = true;
  String? _error;
  UserProfile? _profile;
  bool _inited = false;
  bool _isPublicView = false;
  int? _targetUserId;
  Map<String, dynamic> _fallbackProfile = <String, dynamic>{};
  String? _participantRole;
  DistanceUserSummary? _viewerSummary;
  DistanceUserSummary? _profileSummary;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    ActivityStatsRefreshService.revision.addListener(_handleStatsChanged);
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    ActivityStatsRefreshService.revision.removeListener(_handleStatsChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleStatsChanged() {
    if (!mounted || _loading) return;
    _loadProfile();
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  double? _readFallbackDouble(List<String> keys) {
    for (final key in keys) {
      final raw = _fallbackProfile[key];
      if (raw == null) continue;
      final parsed = double.tryParse(raw.toString().trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _readFallbackInt(List<String> keys) {
    for (final key in keys) {
      final raw = _fallbackProfile[key];
      if (raw == null) continue;
      final parsed = int.tryParse(raw.toString().trim());
      if (parsed != null) return parsed;
    }
    return null;
  }

  DistanceUserSummary _mergeSummary({
    required int userId,
    required String displayName,
    required String role,
    required String profileImageUrl,
    required String district,
    required String province,
    required String status,
    DistanceUserSummary? summary,
    UserProfile? profile,
    bool useFallback = false,
  }) {
    final fallbackTotalKm = useFallback
        ? _readFallbackDouble(const <String>[
            'total_km',
            'totalKm',
            'completed_distance_km',
            'completedDistanceKm',
            'distance_km',
            'distanceKm',
          ])
        : null;
    final fallbackCompleted = useFallback
        ? _readFallbackInt(const <String>[
            'completed_count',
            'completedCount',
            'completed_events',
            'completedEvents',
            'activity_count',
            'activityCount',
          ])
        : null;
    final fallbackJoined = useFallback
        ? _readFallbackInt(const <String>['joined_count', 'joinedCount'])
        : null;
    final fallbackPost = useFallback
        ? _readFallbackInt(const <String>['post_count', 'postCount'])
        : null;

    final totalKmCandidates = <double>[
      if (summary?.totalKm != null) summary!.totalKm!,
      if (profile?.totalKm != null) profile!.totalKm!,
      if (fallbackTotalKm != null) fallbackTotalKm,
    ];
    final completedCountCandidates = <int>[
      if (summary != null) summary.completedCount,
      if (profile != null) profile.joinedCount + profile.postCount,
      if (fallbackCompleted != null) fallbackCompleted,
      if (fallbackJoined != null || fallbackPost != null)
        (fallbackJoined ?? 0) + (fallbackPost ?? 0),
    ];

    return DistanceUserSummary(
      userId: summary != null && summary.userId > 0 ? summary.userId : userId,
      displayName: summary != null && summary.displayName.trim().isNotEmpty
          ? summary.displayName
          : displayName,
      role: summary != null && summary.role.trim().isNotEmpty
          ? summary.role
          : role,
      totalKm: totalKmCandidates.isEmpty
          ? null
          : totalKmCandidates.reduce((a, b) => a > b ? a : b),
      joinedCount: <int>[
        if (summary != null) summary.joinedCount,
        if (profile != null) profile.joinedCount,
        if (fallbackJoined != null) fallbackJoined,
      ].fold<int>(0, (best, value) => value > best ? value : best),
      completedCount: completedCountCandidates.isEmpty
          ? 0
          : completedCountCandidates.reduce((a, b) => a > b ? a : b),
      unrecordedCount: summary?.unrecordedCount ?? 0,
      postCount: <int>[
        if (summary != null) summary.postCount,
        if (profile != null) profile.postCount,
        if (fallbackPost != null) fallbackPost,
      ].fold<int>(0, (best, value) => value > best ? value : best),
      profileImageUrl:
          summary != null && summary.profileImageUrl.trim().isNotEmpty
              ? summary.profileImageUrl
              : profileImageUrl,
      district: summary != null && summary.district.trim().isNotEmpty
          ? summary.district
          : district,
      province: summary != null && summary.province.trim().isNotEmpty
          ? summary.province
          : province,
      status: summary != null && summary.status.trim().isNotEmpty
          ? summary.status
          : status,
    );
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      UserProfile? currentViewerProfile;
      final profile = _isPublicView && (_targetUserId ?? 0) > 0
          ? await UserProfileService.fetchUserProfileById(
              _targetUserId!,
              fallbackUserJson: _fallbackProfile,
            )
          : await UserProfileService.fetchCurrentUserProfile();
      DistanceUserSummary? viewerSummary;
      DistanceUserSummary? profileSummary;
      if (_isPublicView) {
        try {
          currentViewerProfile =
              await UserProfileService.fetchCurrentUserProfile();
        } catch (_) {
          currentViewerProfile = null;
        }
        try {
          viewerSummary = await UserDistanceService.fetchCurrentUserSummary();
        } catch (_) {
          viewerSummary = null;
        }
        try {
          profileSummary = await UserDistanceService.fetchUserSummaryById(
            _targetUserId!,
          );
        } catch (_) {
          profileSummary = null;
        }
      } else {
        try {
          profileSummary = await UserDistanceService.fetchCurrentUserSummary();
        } catch (_) {
          profileSummary = null;
        }
      }
      if (_isPublicView) {
        viewerSummary = _mergeSummary(
          userId: currentViewerProfile?.id ?? (viewerSummary?.userId ?? 0),
          displayName: currentViewerProfile?.displayName ??
              viewerSummary?.displayName ??
              'User',
          role: viewerSummary?.role ?? '',
          profileImageUrl: currentViewerProfile?.profileImageUrl ??
              viewerSummary?.profileImageUrl ??
              '',
          district:
              currentViewerProfile?.district ?? viewerSummary?.district ?? '',
          province:
              currentViewerProfile?.province ?? viewerSummary?.province ?? '',
          status: currentViewerProfile?.status ?? viewerSummary?.status ?? '',
          summary: viewerSummary,
          profile: currentViewerProfile,
        );
        profileSummary = _mergeSummary(
          userId: profile.id,
          displayName: profile.displayName,
          role: _participantRole ?? profileSummary?.role ?? '',
          profileImageUrl: profile.profileImageUrl,
          district: profile.district,
          province: profile.province,
          status: profile.status,
          summary: profileSummary,
          profile: profile,
          useFallback: true,
        );
      } else {
        profileSummary = _mergeSummary(
          userId: profile.id,
          displayName: profile.displayName,
          role: profileSummary?.role ?? '',
          profileImageUrl: profile.profileImageUrl,
          district: profile.district,
          province: profile.province,
          status: profile.status,
          summary: profileSummary,
          profile: profile,
        );
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _viewerSummary = viewerSummary;
        _profileSummary = profileSummary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    final args = (ModalRoute.of(context)?.settings.arguments is Map)
        ? Map<String, dynamic>.from(
            ModalRoute.of(context)!.settings.arguments as Map,
          )
        : <String, dynamic>{};

    _targetUserId = int.tryParse((args["userId"] ?? "").toString());
    _participantRole = (args["role"] ?? "").toString().trim();
    _isPublicView = args["public"] == true && (_targetUserId ?? 0) > 0;
    _fallbackProfile = <String, dynamic>{
      "id": _targetUserId,
      "name": (args["displayName"] ?? "").toString(),
      "first_name": (args["firstName"] ?? "").toString(),
      "last_name": (args["lastName"] ?? "").toString(),
      "profile_image_url": (args["profileImageUrl"] ?? "").toString(),
      "total_km": args["totalKm"],
      "completed_count": args["completedCount"],
      "joined_count": args["joinedCount"],
      "post_count": args["postCount"],
      "district": (args["district"] ?? "").toString(),
      "province": (args["province"] ?? "").toString(),
      "status": (args["status"] ?? "").toString(),
    };

    _loadProfile();
  }

  String _normalizedUrl(String input) => ConfigService.resolveUrl(input);

  String _publicRoleLabel() {
    final role = _participantRole?.trim().toLowerCase() ?? "";
    if (role == "host") return tr('host');
    if (role.isNotEmpty) {
      return "${role[0].toUpperCase()}${role.substring(1)}";
    }
    return tr('runner_profile');
  }

  Widget _imageThumb({
    required String url,
    required String emptyText,
    required double height,
  }) {
    final resolved = _normalizedUrl(url);
    if (resolved.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        alignment: Alignment.center,
        child: Text(
          emptyText,
          style: const TextStyle(color: Colors.black54),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openImagePreview(resolved),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          resolved,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: height,
            color: const Color(0xFFF1F5F9),
            alignment: Alignment.center,
            child: Text(tr('cannot_load_image')),
          ),
        ),
      ),
    );
  }

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => SizedBox(
                height: 220,
                child: Center(child: Text(tr('cannot_load_image'))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD7DEEA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1565C0)),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? "-" : value),
          ),
        ],
      ),
    );
  }

  Widget _addressCard(UserProfile profile) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7DEEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('address_details'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _line(tr('full_address'), profile.address),
          _line(tr('house_no'), profile.addressHouseNo),
          _line(tr('floor'), profile.addressFloor),
          _line(tr('building'), profile.addressBuilding),
          _line(tr('road'), profile.addressRoad),
          _line(tr('subdistrict'), profile.addressSubdistrict),
          _line(tr('province'), profile.province),
          _line(tr('district'), profile.district),
          _line(tr('postal_code'), profile.addressPostalCode),
        ],
      ),
    );
  }

  Widget _publicProfileBody(UserProfile profile) {
    final displayedTotalKm = _profileSummary?.totalKm ?? 0;
    final displayedCompletedCount = _profileSummary?.completedCount ?? 0;
    final displayedDistanceText = formatDistanceKm(displayedTotalKm);
    final publicLocation = profile.publicLocation;
    final aboutBits = <String>[
      _publicRoleLabel(),
      if (publicLocation.isNotEmpty) publicLocation,
    ];
    final comparisonText = (_viewerSummary?.userId != null &&
            _viewerSummary!.userId != profile.id &&
            _viewerSummary?.totalKm != null &&
            displayedTotalKm > 0 &&
            displayedCompletedCount > 0)
        ? compareUserDistance(
            currentUserKm: _viewerSummary!.totalKm!,
            otherUserKm: displayedTotalKm,
            userName: profile.displayName,
            mode: ComparisonTextMode.profile,
          )
        : null;
    final memberCompletedSummary = _isPublicView
        ? tr(
            'member_completed_summary',
            params: {
              'distance': displayedDistanceText,
              'count': displayedCompletedCount.toString(),
            },
          )
        : null;
    final statCards = <Widget>[
      _statTile(
        icon: Icons.route,
        label: tr('completed_distance'),
        value: displayedDistanceText,
      ),
      _statTile(
        icon: Icons.event_available,
        label: tr('completed_events'),
        value: displayedCompletedCount.toString(),
      ),
    ];

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: tr('public_profile'),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: const Color(0xFFDDE6FF),
                  backgroundImage: _normalizedUrl(profile.profileImageUrl)
                          .isEmpty
                      ? null
                      : NetworkImage(_normalizedUrl(profile.profileImageUrl)),
                  child: _normalizedUrl(profile.profileImageUrl).isEmpty
                      ? Text(
                          profile.displayName.isNotEmpty
                              ? profile.displayName
                                  .substring(0, 1)
                                  .toUpperCase()
                              : "?",
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1565C0),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                Text(
                  profile.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (aboutBits.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    aboutBits.join(" | "),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _section(
            title: tr('running_summary'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var index = 0; index < statCards.length; index++) ...[
                      if (index > 0) const SizedBox(width: 10),
                      statCards[index],
                    ],
                  ],
                ),
                if (comparisonText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    comparisonText,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (memberCompletedSummary != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    memberCompletedSummary,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _section(
            title: tr('shared_info'),
            child: Column(
              children: [
                _line(tr('display_name'), profile.displayName),
                _line(tr('role'), _publicRoleLabel()),
                _line(tr('location'), publicLocation),
                _line(tr('status'), profile.status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Text(_isPublicView ? tr('runner_profile') : tr('user_info')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _loadProfile,
                          child: Text(tr('retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : _isPublicView
                  ? _publicProfileBody(_profile!)
                  : RefreshIndicator(
                      onRefresh: _loadProfile,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _section(
                            title: tr('profile'),
                            child: Row(
                              children: [
                                ClipOval(
                                  child: SizedBox(
                                    width: 74,
                                    height: 74,
                                    child: _imageThumb(
                                      url: _profile!.profileImageUrl,
                                      emptyText: tr('no_image'),
                                      height: 74,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _profile!.displayName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _profile!.email.isEmpty
                                            ? "-"
                                            : _profile!.email,
                                        style: const TextStyle(
                                            color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _section(
                            title: tr('personal_details'),
                            child: Column(
                              children: [
                                _line(tr('first_name'), _profile!.firstName),
                                _line(tr('last_name'), _profile!.lastName),
                                _line(tr('email'), _profile!.email),
                                _line(tr('phone'), _profile!.phone),
                                _addressCard(_profile!),
                                _line(tr('status'), _profile!.status),
                              ],
                            ),
                          ),
                          _section(
                            title: tr('document'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('id_card_image'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _imageThumb(
                                  url: _profile!.nationalIdImageUrl,
                                  emptyText: tr('no_document_image'),
                                  height: 160,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
