import 'package:flutter/material.dart';
import '../status/success.dart';

class CancelPage extends StatelessWidget {
  final Map<String, dynamic> event;
  const CancelPage({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    Widget buildButton({
      required String text,
      required Color bgColor,
      required Color textColor,
      required Color borderColor,
      required VoidCallback onPressed,
    }) {
      return Expanded(
        child: SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: textColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: borderColor, width: 1.5),
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF00C9A7),
      body: SafeArea(
        child: Center(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.7,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/user/icons/cancel.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.cancel, size: 120),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Canceling this event cannot be undone. Are you sure you want to proceed?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 50),
                Row(
                  children: [
                    buildButton(
                      text: "Yes",
                      bgColor: Colors.white,
                      textColor: Colors.black,
                      borderColor: const Color(0xffFF4444),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SuccessPage(
                              title: 'Cancel',
                              subtitle: 'successful',
                              buttonText: 'Back',
                              blockSystemBack: true,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    buildButton(
                      text: "No",
                      bgColor: Colors.white,
                      textColor: Colors.black,
                      borderColor: const Color(0xffFF4444),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}