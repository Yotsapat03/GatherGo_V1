import 'package:flutter/material.dart';

class SpotJoinPage extends StatelessWidget {
  final Map<String, dynamic> event;

  const SpotJoinPage({super.key, required this.event});

  static const String _base = 'assets/images/user';

  String _resolveImage(String raw) {
    final p = raw.trim();
    if (p.isEmpty) return '';

    // ถ้าเป็น path ของโปรเจกต์คุณแล้ว
    if (p.startsWith('$_base/')) return p;

    // รองรับ path เก่าของเพื่อน
    if (p.startsWith('assets/spots/')) {
      return p.replaceFirst('assets/spots/', '$_base/spots/');
    }
    if (p.startsWith('assets/icons/')) {
      return p.replaceFirst('assets/icons/', '$_base/icons/');
    }
    if (p.startsWith('assets/events/')) {
      return p.replaceFirst('assets/events/', '$_base/events/');
    }

    return p;
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _resolveImage((event['image'] ?? '').toString());
    final distance = (event['distance'] ?? '').toString();
    final date = (event['date'] ?? '').toString();
    final location = (event['location'] ?? '').toString();
    final organizer = (event['organizer'] ?? '').toString();
    final description = (event['description'] ?? '').toString();
    final isJoined = event['isJoined'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text('Spot Join'),
        backgroundColor: const Color(0xFF00C9A7),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== Image =====
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imagePath.isNotEmpty
                    ? Image.asset(
                        imagePath,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallbackImage(height: 200),
                      )
                    : _fallbackImage(height: 200),
              ),
              const SizedBox(height: 14),

              // ===== Title-ish =====
              Text(
                organizer.isEmpty ? 'Spot' : organizer,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              _infoRow(Icons.directions_run, 'Distance', distance),
              const SizedBox(height: 8),
              _infoRow(Icons.calendar_today, 'Date', date),
              const SizedBox(height: 8),
              _infoRow(Icons.location_on, 'Location', location),

              const SizedBox(height: 14),

              // ===== Description =====
              if (description.trim().isNotEmpty) ...[
                const Text(
                  'Description',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(description, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
              ],

              // ===== Join Button =====
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isJoined
                      ? null
                      : () {
                          // ✅ ตอนนี้ยังเป็น mock data
                          // ถ้าจะเชื่อม backend ค่อยมาเติมตรงนี้ได้
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Joined successfully')),
                          );
                          Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C9A7),
                    disabledBackgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    isJoined ? 'Already Joined' : 'Join Spot',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static Widget _fallbackImage({double? width, double? height}) {
    return Container(
      width: width ?? double.infinity,
      height: height ?? 150,
      color: const Color(0xFFEFEFEF),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, size: 32),
    );
  }
}
