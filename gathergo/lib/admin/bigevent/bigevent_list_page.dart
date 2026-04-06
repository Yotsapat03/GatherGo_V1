import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../models/organization.dart';
import 'add_organizer_page.dart';
import 'organizer_detail_page.dart';

class BigEventListPage extends StatefulWidget {
  const BigEventListPage({super.key});

  @override
  State<BigEventListPage> createState() => _BigEventListPageState();
}

class _BigEventListPageState extends State<BigEventListPage> {
  final _search = TextEditingController();

  bool _loading = false;
  String? _error;

  List<Organization> _all = [];

  String get _baseUrl => ConfigService.getBaseUrl();

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _search.addListener(() => setState(() {}));
    _loadOrganizations();
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _search.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  Organization _fromJson(Map<String, dynamic> j) {
    return Organization(
      id: (j["id"] ?? "").toString(),
      name: (j["name"] ?? "").toString(),
      email: (j["email"] ?? "").toString(),
      phone: (j["phone"] ?? "").toString(),
      address: (j["address"] ?? "").toString(),
      businessProfile: (j["description"] ?? "").toString(),
      organizer: "",
      imageUrl: j["image_url"]?.toString(),
      imagePath: null,
    );
  }

  Future<void> _loadOrganizations() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse("$_baseUrl/api/organizations");
      final res = await http.get(uri, headers: {
        "Accept": "application/json"
      }).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception(
            "GET /api/organizations failed (${res.statusCode})\n${res.body}");
      }

      final data = jsonDecode(res.body);
      if (data is! List) throw Exception("Invalid response: not a list");

      final list = data
          .map((e) => _fromJson((e as Map).cast<String, dynamic>()))
          .toList()
          .cast<Organization>();

      if (!mounted) return;
      setState(() => _all = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Organization> _filtered(List<Organization> items) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return items;

    return items.where((o) {
      return o.name.toLowerCase().contains(q) ||
          o.email.toLowerCase().contains(q) ||
          o.phone.toLowerCase().contains(q) ||
          o.address.toLowerCase().contains(q) ||
          o.businessProfile.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _goCreateOrganization() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddOrganizerPage()),
    );

    if (result == true) {
      await _loadOrganizations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('organization_created'))),
      );
    }
  }

  Future<void> _goDetail(Organization org) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrganizerDetailPage(org: org)),
    );

    if (result == true) {
      await _loadOrganizations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('organization_updated'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered(_all);

    Widget content;
    if (_loading && _all.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _all.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (items.isEmpty) {
      content = Center(
        child: Text(_t('no_organizations_yet')),
      );
    } else {
      content = ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final org = items[index];
          return _OrgTile(org: org, onView: () => _goDetail(org));
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        // ✅ ให้ชื่อหน้าตรงกับสิ่งที่แสดงจริง
        title: Text(_t('organization_list')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: _t('refresh'),
            onPressed: _loading ? null : _loadOrganizations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: _t('search_ellipsis'),
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadOrganizations,
                child: content is ListView
                    ? content
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: Center(child: content),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _goCreateOrganization,
        backgroundColor: Colors.redAccent,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  final Organization org;
  final VoidCallback onView;

  const _OrgTile({required this.org, required this.onView});

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, fontSize: 14),
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = (org.imageUrl ?? '').trim();
    final imgUrl = raw.isEmpty ? null : ConfigService.resolveUrl(raw);

    final Widget leading = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 56,
        width: 56,
        color: Colors.grey.shade200,
        child: (imgUrl == null)
            ? const Icon(Icons.apartment, color: Colors.black54)
            : Image.network(
                imgUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.black54),
              ),
      ),
    );

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line(AdminStrings.text('name'), org.name),
                  _line(AdminStrings.text('email'), org.email),
                  _line(AdminStrings.text('phone_number'), org.phone),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onView,
              child: Text(AdminStrings.text('view')),
            ),
          ],
        ),
      ),
    );
  }
}
