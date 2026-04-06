import 'package:flutter/material.dart';
import '../data/audit_log/audit_log_api.dart';

class UserAuditLogPage extends StatefulWidget {
  const UserAuditLogPage({super.key});

  @override
  State<UserAuditLogPage> createState() => _UserAuditLogPageState();
}

class _UserAuditLogPageState extends State<UserAuditLogPage> {
  final _search = TextEditingController();
  Future<List<AuditLogEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _future = AuditLogApi.fetchUserLogs();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = AuditLogApi.fetchUserLogs(q: _search.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'User Audit Log',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search user / action / id...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AuditLogEntry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(snap.error.toString()));
                }

                final items = snap.data ?? [];
                final q = _search.text.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? items
                    : items.where((e) {
                        return e.actorName.toLowerCase().contains(q) ||
                            e.actorCode.toLowerCase().contains(q) ||
                            e.action.toLowerCase().contains(q);
                      }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No audit logs found.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _UserTile(entry: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AuditLogEntry entry;
  const _UserTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final dt = entry.createdAt;
    final dtText = '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('User', '${entry.actorName} (${entry.actorCode})'),
              _row('Action', entry.action),
              _row('Time', entry.createdAt.toIso8601String()),
              _row('Entity', '${entry.entityType ?? '-'}  #${entry.entityId ?? '-'}'),
            ],
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              offset: Offset(0, 4),
              color: Color(0x1F000000),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDAD8FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.person_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.actorName} • ${entry.actorCode}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(entry.action,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(dtText, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            ),
            Text(
              'Detail',
              style: TextStyle(
                color: Colors.indigo.shade600,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
