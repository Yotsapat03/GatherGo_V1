import 'package:flutter/foundation.dart';

class ActivityStatsRefreshService {
  ActivityStatsRefreshService._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyStatsChanged() {
    revision.value = revision.value + 1;
  }
}
