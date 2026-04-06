import '../localization/user_strings.dart';

enum ComparisonTextMode { popup, memberList, profile }

String formatDistanceKm(double km) {
  final normalized = km.abs();
  if (normalized < 0.000001) return "0 km";
  final hasSingleDecimal = ((normalized * 10) % 1).abs() < 0.000001;
  final fixed = normalized % 1 == 0
      ? normalized.toStringAsFixed(0)
      : normalized.toStringAsFixed(hasSingleDecimal ? 1 : 2);
  final trimmed = fixed.replaceFirst(RegExp(r'([.]*0+)$'), '');
  return "$trimmed km";
}

String compareUserDistance({
  required double currentUserKm,
  required double otherUserKm,
  required String userName,
  required ComparisonTextMode mode,
}) {
  const epsilon = 0.000001;
  final safeName = userName.trim().isEmpty
      ? UserStrings.text('this_runner')
      : userName.trim();
  final diff = (currentUserKm - otherUserKm).abs();
  final diffText = formatDistanceKm(diff);
  final isEqual = diff < epsilon;

  switch (mode) {
    case ComparisonTextMode.popup:
      if (isEqual) {
        return userName.trim().isEmpty
            ? UserStrings.text('compare_popup_done_self')
            : UserStrings.text(
                'compare_popup_done_other',
                params: {'name': safeName},
              );
      }
      if (currentUserKm < otherUserKm) {
        if (diff < 10) {
          return UserStrings.text(
            'compare_popup_close_to',
            params: {'name': safeName, 'distance': diffText},
          );
        }
        return UserStrings.text(
          'compare_popup_behind',
          params: {'name': safeName, 'distance': diffText},
        );
      }
      if (diff > 10) {
        return UserStrings.text(
          'compare_popup_ahead_far',
          params: {'name': safeName, 'distance': diffText},
        );
      }
      return UserStrings.text(
        'compare_popup_ahead_near',
        params: {'name': safeName, 'distance': diffText},
      );
    case ComparisonTextMode.memberList:
      if (isEqual) {
        return UserStrings.text(
          'compare_member_equal',
          params: {'name': safeName},
        );
      }
      if (currentUserKm < otherUserKm) {
        return UserStrings.text(
          'compare_member_other_ahead',
          params: {'name': safeName, 'distance': diffText},
        );
      }
      return UserStrings.text(
        'compare_member_you_ahead',
        params: {'name': safeName, 'distance': diffText},
      );
    case ComparisonTextMode.profile:
      if (isEqual) {
        return UserStrings.text('compare_profile_equal');
      }
      if (currentUserKm < otherUserKm) {
        return UserStrings.text(
          'compare_profile_behind',
          params: {'distance': diffText},
        );
      }
      return UserStrings.text(
        'compare_profile_ahead',
        params: {'distance': diffText},
      );
  }
}
