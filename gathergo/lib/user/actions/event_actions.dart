import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../data/mock_store.dart';
import '../data/event_mapper.dart';

class EventActions {
  static Future<void> join(
    BuildContext context, {
    required Map<String, dynamic> event,
    int fallbackIndex = 0,
  }) async {
    final int eventId = EventMapper.id(event, fallback: fallbackIndex);
    final String title = EventMapper.title(event);
    final double fee = EventMapper.fee(event);

    // ✅ เก็บลง joined list ของ mock ก่อน (ระบบคุณ)
    MockStore.joinEvent(event);

    // ✅ ปิด bottom sheet ถ้ามี (ถ้าไม่มีจะไม่พัง)
    await Navigator.maybePop(context);

    // ✅ ไปหน้า Join flow (ระบบ route ของคุณ)
    if (!context.mounted) return;

    Navigator.pushNamed(
      context,
      AppRoutes.userEventJoin,
      arguments: {
        'eventId': eventId,
        'title': title,
        'fee': fee,
        'event': event,
      },
    );
  }
}