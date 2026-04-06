import 'package:flutter/material.dart';

class SpotCard extends StatelessWidget {
  final Map<String, dynamic> spot;
  const SpotCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // ✅ เปลี่ยนจาก popup เป็นไปหน้า detail
        Navigator.pushNamed(context, '/user/spot/detail', arguments: spot);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(spot["title"] ?? "-"),
      ),
    );
  }
}