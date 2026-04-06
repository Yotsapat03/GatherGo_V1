import 'package:flutter/material.dart';
import '../../app_routes.dart';

class ReportPage extends StatefulWidget {
  final Map<String, dynamic> event;
  const ReportPage({super.key, required this.event});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
            height: MediaQuery.of(context).size.height * 0.75,
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
              children: [
                Image.asset(
                  'assets/icons/cancel.png',
                  width: 60,
                  height: 60,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Report to us",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: "Please describe the issue in detail...",
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    buildButton(
                      text: "Submit",
                      bgColor: Colors.white,
                      textColor: Colors.black,
                      borderColor: const Color(0xffFF4444),
                      onPressed: () {
                        if (_controller.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please enter report details."),
                            ),
                          );
                          return;
                        }

                        // TODO: ใส่ API จริงภายหลัง (ส่ง report)
                        Navigator.pushNamed(
                          context,
                          AppRoutes.userSuccess,
                          arguments: {
                            "title": "Submit",
                            "subtitle": "successful",
                            "buttonText": "Back",
                            "popUntilRouteName": AppRoutes.userHome, // หรือเปลี่ยนเป็นหน้าที่คุณอยากกลับ
                            "autoSeconds": 2,
                            "blockSystemBack": true,
                          },
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}