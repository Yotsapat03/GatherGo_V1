import 'package:flutter/material.dart';

class SpotJoinCard extends StatelessWidget {
  final Map<String, dynamic> spot;
  final VoidCallback? onJoin;

  const SpotJoinCard({
    super.key,
    required this.spot,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final bool isJoined = spot["isJoined"] == true;
    final String imagePath = (spot["image"] ?? "").toString().trim();
    final bool isNetworkImage =
        imagePath.startsWith("http://") || imagePath.startsWith("https://");

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Spot Information",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (imagePath.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isNetworkImage
                  ? Image.network(
                      imagePath,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    )
                  : Image.asset(
                      imagePath,
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
          _info("Title", spot["title"]),
          _info("Host", spot["host"]),
          _info("Date", spot["date"]),
          _info("Time", spot["time"]),
          _info("Location", spot["location"]),
          if (spot["description"] != null)
            _info("Description", spot["description"]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: isJoined ? null : () => onJoin?.call(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: const Color(0xFF845104),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF845104), width: 1.5),
                ),
              ),
              child: Text(
                isJoined ? "Joined" : "Join",
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        "$label: ${value ?? "-"}",
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
