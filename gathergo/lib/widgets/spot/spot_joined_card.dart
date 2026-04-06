import 'package:flutter/material.dart';
import 'spot_join_card.dart';

class SpotJoinedCard extends StatelessWidget {
  final Map<String, dynamic> spot;
  final VoidCallback? onJoin;

  const SpotJoinedCard({
    super.key,
    required this.spot,
    this.onJoin,
  });

  // ✅ FIX: normalize path กัน path เก่า/ผิด
  String _normalizeImagePath(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return p;

    // ถ้าเคยส่งมาเป็น assets/images/user/events/... (ผิดสำหรับ spot)
    if (p.startsWith('assets/images/user/events/')) {
      final name = p.split('/').last; // event1.png event2.png ...
      // map ให้เป็น spot1.png/spot2.png ถ้าคุณต้องการ (ไม่เดา) -> ใช้ชื่อเดิมก่อน
      // แต่ถ้าอยากชัวร์ให้เปลี่ยน data ใน mock_store เป็น user/spots อยู่แล้ว
      return 'assets/images/user/spots/$name';
    }

    // เคสเก่า: assets/images/spots/xxx.png
    if (p.startsWith('assets/images/spots/')) {
      final name = p.replaceFirst('assets/images/spots/', '');
      return 'assets/images/user/spots/$name';
    }

    // เคสเก่า: assets/spots/xxx.png
    if (p.startsWith('assets/spots/')) {
      final name = p.replaceFirst('assets/spots/', '');
      return 'assets/images/user/spots/$name';
    }

    // ถ้าเป็นของถูกแล้ว
    if (p.startsWith('assets/images/')) return p;

    return p;
  }

  @override
  Widget build(BuildContext context) {
    final rawPath = (spot["image"] ?? "").toString();
    final imagePath = _normalizeImagePath(rawPath);
    final isNetworkImage =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');

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
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    children: [
                      const _SheetHeader(),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          child: SpotJoinCard(
                            spot: spot,
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
        height: 140,
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
              child: imagePath.isEmpty
                  ? Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported),
                    )
                  : isNetworkImage
                      ? Image.network(
                          imagePath,
                          width: 90,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        )
                      : Image.asset(
                          imagePath,
                          width: 90,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (spot["title"] ?? "Spot").toString(),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text("Host: ${spot["host"] ?? "-"}",
                        style: const TextStyle(fontSize: 12)),
                    Text("Date: ${spot["date"] ?? "-"}",
                        style: const TextStyle(fontSize: 12)),
                    Text("Time: ${spot["time"] ?? "-"}",
                        style: const TextStyle(fontSize: 12)),
                    Text("Location: ${spot["location"] ?? "-"}",
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
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
              "Spot Details",
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
