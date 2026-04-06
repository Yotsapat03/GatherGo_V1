import 'package:flutter/material.dart';
import '../utils/url_utils.dart';

// ปรับชนิดให้ตรงกับของคุณ (คุณใช้ EventMediaItem อยู่แล้ว)
class GalleryPreviewPage extends StatefulWidget {
  final List<dynamic> items; // ถ้าเป็น List<EventMediaItem> ก็เปลี่ยนเป็นแบบนั้นได้
  final int initialIndex;

  const GalleryPreviewPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<GalleryPreviewPage> createState() => _GalleryPreviewPageState();
}

class _GalleryPreviewPageState extends State<GalleryPreviewPage> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ดึง url จาก item ให้รองรับได้หลายแบบ
  String _getUrl(dynamic item) {
    // ถ้าของคุณเป็น EventMediaItem ที่มี field fileUrl
    try {
      final url = item.fileUrl as String;
      return fixLocalhostForEmulator(url);
    } catch (_) {}

    // ถ้า item เป็น Map
    if (item is Map) {
      final url = (item['file_url'] ?? item['fileUrl'] ?? '') as String;
      return fixLocalhostForEmulator(url);
    }

    // fallback
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Gallery ${_index + 1}/$total'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: total,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final url = _getUrl(widget.items[i]);

          return Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (c, w, p) {
                  if (p == null) return w;
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
