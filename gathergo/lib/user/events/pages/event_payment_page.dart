import 'package:flutter/material.dart';
import '../../../app_routes.dart';

class EventPaymentPage extends StatefulWidget {
  const EventPaymentPage({super.key});

  @override
  State<EventPaymentPage> createState() => _EventPaymentPageState();
}

class _EventPaymentPageState extends State<EventPaymentPage> {
  String method = 'promptpay'; // promptpay | bank

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments is Map)
        ? (ModalRoute.of(context)!.settings.arguments as Map)
        : <String, dynamic>{};

    final String title = (args['title'] ?? 'Big Event').toString();
    final dynamic rawFee = args['fee'] ?? 0;
    final double fee =
        (rawFee is num) ? rawFee.toDouble() : double.tryParse(rawFee.toString()) ?? 0.0;

    final bookingId = args['bookingId'];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: const Color(0xFF00C9A7),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Booking ID: $bookingId'),
            const SizedBox(height: 6),
            Text('Amount: ${fee.toStringAsFixed(2)} THB'),

            const SizedBox(height: 18),
            const Text('Choose payment method', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            RadioListTile<String>(
              value: 'promptpay',
              groupValue: method,
              onChanged: (v) => setState(() => method = v!),
              title: const Text('PromptPay'),
              subtitle: const Text('Pay via PromptPay QR'),
            ),
            RadioListTile<String>(
              value: 'bank',
              groupValue: method,
              onChanged: (v) => setState(() => method = v!),
              title: const Text('Bank Transfer'),
              subtitle: const Text('Pay via bank transfer'),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C9A7),
                ),
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.userEventEvidence,
                    arguments: {
                      ...args,
                      'paymentMethod': method,
                    },
                  );
                },
                child: const Text('Upload Evidence'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}