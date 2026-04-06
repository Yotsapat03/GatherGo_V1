import 'package:flutter/material.dart';
import '../../constants/asset_path.dart';
import 'event_join_card.dart';

class EventJoinedCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback? onJoin;

  const EventJoinedCard({
    super.key,
    required this.event,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPaid = event['isPaid'] == true;

    // ✅ normalize path ให้ถูกต้องกับ assets ปัจจุบัน
    final imagePath = AssetPath.normalize((event['image'] ?? '').toString());

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    children: [
                      const _SheetHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: EventJoinCard(
                            event: event,
                            onJoin: onJoin,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
      child: Container(
        height: 150,
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Image.asset(
                imagePath,
                width: 90,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackImage(width: 90, height: 150),
              ),
            ),
            Expanded(
              flex: 1,
              child: _infoRow(isPaid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(bool isPaid) {
    return Container(
      color: const Color(0xFFD9D9D9),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoColumn("Total distance: ", (event['total_distance'] ?? '0').toString()),
                  _infoColumn("Date: ", (event['date'] ?? '').toString()),
                  _infoColumn("Location: ", (event['location'] ?? '').toString()),
                  _infoColumn("Organizer: ", (event['organizer'] ?? '').toString()),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: [
                  const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF95FFA1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    child: Text(
                      isPaid ? "Paid" : "Existing",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoColumn(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text(text, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              "Event Details",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

Widget _fallbackImage({double? width, double? height}) {
  return Container(
    width: width,
    height: height,
    color: const Color(0xFFEFEFEF),
    alignment: Alignment.center,
    child: const Icon(Icons.image_not_supported_outlined, size: 24),
  );
}
