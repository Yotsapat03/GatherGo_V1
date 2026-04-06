import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'big_event_model.dart';

class BigEventPage extends StatefulWidget {
  const BigEventPage({super.key});

  @override
  State<BigEventPage> createState() => _BigEventPageState();
}

class _BigEventPageState extends State<BigEventPage> {
  late Future<List<BigEvent>> _future;

  // ✅ เลือกอันเดียวตามที่คุณรัน
  static const String _baseUrl = "http://10.0.2.2:3000"; // Android Emulator
  // static const String _baseUrl = "http://localhost:3000"; // Web/Desktop

  Future<List<BigEvent>> fetchBigEvents() async {
    final uri = Uri.parse("$_baseUrl/api/big-events");
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body["data"] as List).cast<dynamic>();

    return raw
        .map((e) => BigEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _future = fetchBigEvents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text("Big Events"),
        backgroundColor: const Color(0xFF00C9A7),
      ),
      body: FutureBuilder<List<BigEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Error: ${snap.error}",
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final events = snap.data ?? [];
          if (events.isEmpty) {
            return const Center(child: Text("No Big Events"));
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = fetchBigEvents());
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = events[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE6EAF2)),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 10,
                        offset: Offset(0, 4),
                        color: Color(0x11000000),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (e.description.isNotEmpty)
                        Text(
                          e.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.place,
                              size: 16, color: Colors.teal),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "${e.meetingPoint} • ${e.city}, ${e.province}",
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.confirmation_number,
                              size: 16, color: Colors.blueGrey),
                          const SizedBox(width: 6),
                          Text(
                            "ID: ${e.id}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}