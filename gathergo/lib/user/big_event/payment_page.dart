import 'dart:math';
import 'package:flutter/material.dart';
import 'package:gathergo/app_routes.dart';

import '../../core/services/config_service.dart';

class EventPaymentPage extends StatefulWidget {
  const EventPaymentPage({super.key});

  @override
  State<EventPaymentPage> createState() => _EventPaymentPageState();
}

class _EventPaymentPageState extends State<EventPaymentPage> {
  bool _inited = false;

  String _bookingId = "";
  Map<String, dynamic> _event = <String, dynamic>{};
  num _amountNum = 0;
  String _currency = "THB";
  String _qrUrl = "";

  /// ✅ baseUrl auto ตาม platform
  /// - Android Emulator -> 10.0.2.2
  /// - iOS Simulator / Web / Desktop -> localhost
  late String _baseUrl = ConfigService.getBaseUrl();

  String _generateBookingId() {
    final now = DateTime.now();
    final rnd = Random().nextInt(900000) + 100000; // 6 หลัก
    String two(int n) => n.toString().padLeft(2, '0');
    return "BK${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}-$rnd";
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _normalizeUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return "";
    if (u.startsWith("http://") || u.startsWith("https://")) return u;

    // ถ้าเป็น path เช่น /uploads/xxx.png -> ต่อ baseUrl ให้
    if (u.startsWith("/")) return "$_baseUrl$u";
    return "$_baseUrl/$u";
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;

    final args =
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ??
            {};

    // ✅ รองรับ override baseUrl จากตอน pushNamed (ถ้าส่งมา)
    final incomingBaseUrl = (args['baseUrl'] ?? '').toString().trim();
    if (incomingBaseUrl.isNotEmpty) {
      _baseUrl = incomingBaseUrl;
    }

    final event = (args['event'] is Map)
        ? Map<String, dynamic>.from(args['event'])
        : <String, dynamic>{};
    _event = event;

    // ✅ bookingId: ต้องมาจาก backend
    final incomingBookingId = (args['bookingId'] ?? '').toString().trim();
    _bookingId = incomingBookingId.isNotEmpty
        ? incomingBookingId
        : _generateBookingId(); // fallback กันหน้าโล่ง (แต่ปกติควรมี)

    // ✅ currency: args ก่อน แล้ว fallback ไป event.currency แล้ว default THB
    _currency = (args['currency'] ?? event['currency'] ?? 'THB')
        .toString()
        .toUpperCase();

    // ✅ amount: args ก่อน ถ้า 0 ค่อย fallback ไป fee/price ใน event
    _amountNum = _toNum(args['amount']);
    if (_amountNum == 0) {
      _amountNum = _toNum(event['fee'] ?? event['price'] ?? 0);
    }

    // ✅ qr: args ก่อน แล้ว fallback ไป qr_url/qrUrl ใน event
    final rawQr =
        (args['qrUrl'] ?? event['qr_url'] ?? event['qrUrl'] ?? '').toString();
    _qrUrl = _normalizeUrl(rawQr);

    debugPrint("### OPEN EventPaymentPage");
    debugPrint("### Payment args=$args");
    debugPrint("### bookingId=$_bookingId");
    debugPrint("### amount=$_amountNum currency=$_currency");
    debugPrint("### rawQr=$rawQr");
    debugPrint("### normalized qrUrl=$_qrUrl");
    debugPrint("### baseUrl=$_baseUrl");

    _inited = true;
  }

  @override
  Widget build(BuildContext context) {
    final title = (_event['title'] ?? 'Big Event').toString();
    final amountText = _amountNum.toStringAsFixed(2);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00C9A7),
        title: const Text("Payment"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),

            Text("Booking ID: ${_bookingId.isEmpty ? '-' : _bookingId}"),
            const SizedBox(height: 6),

            Text(
              "Amount: $amountText $_currency",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 16),

            const Text(
              "Scan QR Code to pay",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),

            Container(
              height: 260,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              alignment: Alignment.center,
              child: _qrUrl.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        "ยังไม่มี QR Code\n(แอดมินยังไม่อัปโหลด หรือ DB qr_url ยังเป็น null)",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red),
                      ),
                    )
                  : Image.network(
                      _qrUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          "โหลดรูป QR ไม่ได้\nเช็คว่า URL เข้าถึงได้จากอุปกรณ์\nbaseUrl=$_baseUrl\nqrUrl=$_qrUrl",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.userEventEvidence,
                  arguments: {
                    'event': _event,
                    'eventId': _event['id'],
                    'bookingId': _bookingId,
                    'amount': _amountNum,
                    'currency': _currency,
                    'qrUrl': _qrUrl,
                    'baseUrl': _baseUrl,
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C9A7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "Upload Evidence",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
