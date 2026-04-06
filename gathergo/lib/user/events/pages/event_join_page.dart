import 'package:flutter/material.dart';
import '../../../app_routes.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/session_service.dart';
import '../../data/event_mapper.dart';

class EventJoinPage extends StatefulWidget {
  const EventJoinPage({super.key});

  @override
  State<EventJoinPage> createState() => _EventJoinPageState();
}

class _EventJoinPageState extends State<EventJoinPage> {
  String? selectedDistance;
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    // ✅ แก้แดง: cast args ให้เป็น Map<String, dynamic>
    final Object? rawArgs = ModalRoute.of(context)?.settings.arguments;

    final Map<String, dynamic> args = (rawArgs is Map)
        ? Map<String, dynamic>.from(rawArgs)
        : <String, dynamic>{};

    // ✅ ดึง event ก้อนหลัก ถ้ามี (จาก BigEvent ส่งมา)
    final Map<String, dynamic> event = (args['event'] is Map)
        ? Map<String, dynamic>.from(args['event'] as Map)
        : <String, dynamic>{};

    // ✅ เลือกแหล่งข้อมูลหลัก: ถ้ามี event ใช้ event ไม่งั้นใช้ args
    final Map<String, dynamic> source = event.isNotEmpty ? event : args;

    // ✅ ใช้ mapper กลาง (กัน key ไม่ตรง)
    final int eventId = EventMapper.id(source, fallback: 0);
    final String title = EventMapper.title(source);
    final double fee = EventMapper.fee(source);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text('Join Event'),
        backgroundColor: const Color(0xFF00C9A7),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('Event ID: $eventId'),
            const SizedBox(height: 6),
            Text('Fee: ${fee.toStringAsFixed(2)} THB'),
            const SizedBox(height: 18),
            const Text(
              'Select distance',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedDistance,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Choose distance',
              ),
              items: const [
                DropdownMenuItem(value: '5K', child: Text('5K')),
                DropdownMenuItem(value: '10K', child: Text('10K')),
                DropdownMenuItem(value: '21K', child: Text('21K')),
              ],
              onChanged: (v) => setState(() => selectedDistance = v),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C9A7),
                ),
                onPressed: (selectedDistance == null || loading)
                    ? null
                    : () async {
                        setState(() => loading = true);

                        // ✅ TODO: ต่อ backend join จริงทีหลัง
                        // ตอนนี้ mock bookingId ไปก่อนให้ flow วิ่งครบ
                        final int bookingId =
                            DateTime.now().millisecondsSinceEpoch;
                        final userId = await SessionService.getCurrentUserId();
                        if (userId == null || userId <= 0) {
                          if (!mounted) return;
                          setState(() => loading = false);
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text('Please log in again.'),
                              ),
                            );
                          return;
                        }
                        final baseUrl = (args['baseUrl'] ??
                                args['base_url'] ??
                                ConfigService.getBaseUrl())
                            .toString();
                        final paymentMode = (source['payment_mode'] ??
                                args['paymentMode'] ??
                                args['payment_mode'] ??
                                'manual_qr')
                            .toString();
                        final eventDate = (source['start_at'] ??
                                source['date'] ??
                                args['eventDate'] ??
                                args['event_date'])
                            ?.toString();
                        final currency =
                            (source['currency'] ?? args['currency'] ?? 'THB')
                                .toString();

                        if (!mounted) return;
                        setState(() => loading = false);

                        Navigator.pushNamed(
                          context,
                          AppRoutes.userEventPayment,
                          arguments: {
                            ...args,
                            // ✅ ส่ง source ที่เป็น Map<String, dynamic> ชัวร์
                            'event': source,
                            'baseUrl': baseUrl,
                            'base_url': baseUrl,
                            'eventId': eventId,
                            'event_id': eventId,
                            'bookingId': bookingId,
                            'booking_id': bookingId,
                            'userId': userId,
                            'user_id': userId,
                            'paymentMode': paymentMode,
                            'payment_mode': paymentMode,
                            'eventTitle': title,
                            'event_title': title,
                            'eventDate': eventDate,
                            'event_date': eventDate,
                            'amount': fee,
                            'price': fee,
                            'currency': currency,
                            'title': title,
                            'fee': fee,
                            'distance': selectedDistance,
                          },
                        );
                      },
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Continue to Payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
