import 'package:flutter/material.dart';

class EventEvidencePage extends StatelessWidget {
  const EventEvidencePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Slip Deprecated')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'The old payment slip upload flow has been removed.\n\n'
          'Please use the new checkout flow:\n'
          '- PromptPay via Stripe (automatic)',
        ),
      ),
    );
  }
}
