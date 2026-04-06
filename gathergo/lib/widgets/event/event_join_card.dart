import 'package:flutter/material.dart';

import '../../user/actions/cancel.dart';
import '../../user/actions/quit.dart';
import '../../user/actions/report.dart';

class EventJoinCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback? onJoin; // ✅ เพิ่มเพื่อให้กด Join แล้วทำงานจริง

  const EventJoinCard({
    super.key,
    required this.event,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPaid = event["isPaid"] == true;
    final bool isJoined = event["isJoined"] == true;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Event Information",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if ((event["image"] ?? "").toString().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                event["image"],
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
            ),

          const SizedBox(height: 12),
          _info("Organizer", event["organizer"]),
          _info("Location", event["location"]),
          _info("Date", event["date"]),
          _info("Total distance", event["total_distance"] ?? "0"),
          if (event["description"] != null) _info("Description", event["description"]),
          const SizedBox(height: 20),

          // ===== Buttons (ตามเพื่อน) =====
          if (isPaid)
            Row(
              children: [
                Expanded(
                  child: _btn(
                    text: "Quit",
                    bg: Colors.red,
                    fg: Colors.white,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => QuitPage(event: event)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _btn(
                    text: "Report",
                    bg: const Color(0xFFFFD54F),
                    fg: const Color(0xFF845104),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReportPage(event: event)),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: _btn(
                text: isJoined ? "Cancel" : "Join",
                bg: isJoined ? Colors.red : const Color(0xFFFFD54F),
                fg: isJoined ? Colors.white : const Color(0xFF845104),
                onTap: () {
                  if (isJoined) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CancelPage(event: event)),
                    );
                  } else {
                    // ✅ กด Join แล้วเรียก callback (BigEventPage จะส่งมา)
                    if (onJoin != null) {
                      onJoin!();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Join (no handler)")),
                      );
                    }
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  static Widget _info(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        "$label: ${value ?? "-"}",
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  static Widget _btn({
    required String text,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
