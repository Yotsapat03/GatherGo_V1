import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/google_maps_support.dart';

class BigEventLocationPickerPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const BigEventLocationPickerPage({
    super.key,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<BigEventLocationPickerPage> createState() =>
      _BigEventLocationPickerPageState();
}

class _BigEventLocationPickerPageState
    extends State<BigEventLocationPickerPage> {
  static const LatLng _fallbackTarget = LatLng(13.7563, 100.5018);

  final TextEditingController _searchCtrl = TextEditingController();
  late LatLng _selected;
  GoogleMapController? _mapController;
  bool _resolvingAddress = false;
  bool _searchingLocation = false;
  String _placeName = '';
  String _province = '';
  String _district = '';
  int _resolveRequestId = 0;
  static const String _googleMapsApiKey = 'AIzaSyCaxlIeEZYrp0hDXlUhYiwWE2apoBx5J2w';

  @override
  void initState() {
    super.initState();
    _selected = (widget.initialLat != null && widget.initialLng != null)
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : _fallbackTarget;
    _resolveAddress();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _setMarker(LatLng value) {
    setState(() => _selected = value);
    _resolveAddress();
  }

  void _confirmSelection() {
    if (_resolvingAddress) return;
    Navigator.pop<Map<String, dynamic>>(context, {
      'latitude': _selected.latitude,
      'longitude': _selected.longitude,
      'place_name': _placeName,
      'province': _province,
      'district': _district,
      'location_display': _locationDisplay,
    });
  }

  String get _locationDisplay {
    if (_district.isEmpty && _province.isEmpty) return '';
    if (_district.isEmpty) return _province;
    if (_province.isEmpty) return _district;
    return '$_province, $_district';
  }

  String _extractPlaceName(
    Placemark? placemark,
    String district,
    String province,
  ) {
    final candidates = <String>[
      (placemark?.name ?? '').trim(),
      (placemark?.thoroughfare ?? '').trim(),
      (placemark?.subLocality ?? '').trim(),
      (placemark?.locality ?? '').trim(),
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final lower = candidate.toLowerCase();
      if (district.isNotEmpty && lower == district.toLowerCase()) continue;
      if (province.isNotEmpty && lower == province.toLowerCase()) continue;
      return candidate;
    }
    return '';
  }

  String _extractProvince(Placemark? placemark) {
    return (placemark?.administrativeArea ??
            placemark?.subAdministrativeArea ??
            placemark?.locality ??
            '')
        .trim();
  }

  String _extractDistrict(Placemark? placemark, String province) {
    final candidates = <String>[
      (placemark?.subLocality ?? '').trim(),
      (placemark?.locality ?? '').trim(),
      (placemark?.subAdministrativeArea ?? '').trim(),
      (placemark?.thoroughfare ?? '').trim(),
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (province.isNotEmpty &&
          candidate.toLowerCase() == province.toLowerCase()) {
        continue;
      }
      return candidate;
    }
    return '';
  }

  Map<String, String> _extractGoogleAddressParts(Map<String, dynamic> result) {
    String province = '';
    String district = '';
    String placeName = '';

    final components = (result['address_components'] is List)
        ? List<Map<String, dynamic>>.from(result['address_components'])
        : const <Map<String, dynamic>>[];

    for (final component in components) {
      final longName = (component['long_name'] ?? '').toString().trim();
      final types = (component['types'] is List)
          ? List<String>.from(component['types'])
          : const <String>[];

      if (longName.isEmpty) continue;

      if (province.isEmpty &&
          (types.contains('administrative_area_level_1') ||
              types.contains('administrative_area_level_2'))) {
        province = longName;
        continue;
      }

      if (district.isEmpty &&
          (types.contains('administrative_area_level_2') ||
              types.contains('administrative_area_level_3') ||
              types.contains('sublocality_level_1') ||
              types.contains('locality'))) {
        district = longName;
        continue;
      }

      if (placeName.isEmpty &&
          (types.contains('premise') ||
              types.contains('point_of_interest') ||
              types.contains('establishment') ||
              types.contains('route') ||
              types.contains('neighborhood'))) {
        placeName = longName;
      }
    }

    if (placeName.isEmpty) {
      placeName = (result['formatted_address'] ?? '').toString().trim();
    }

    if (district.isNotEmpty &&
        province.isNotEmpty &&
        district.toLowerCase() == province.toLowerCase()) {
      district = '';
    }

    return <String, String>{
      'place_name': placeName,
      'province': province,
      'district': district,
    };
  }

  Future<Map<String, String>?> _reverseGeocodeWithGoogle() async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '${_selected.latitude},${_selected.longitude}',
      'language': 'th',
      'region': 'th',
      'key': _googleMapsApiKey,
    });
    final res = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(ConfigService.requestTimeout);
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final results = (decoded['results'] is List)
        ? List<Map<String, dynamic>>.from(decoded['results'])
        : const <Map<String, dynamic>>[];
    if (results.isEmpty) return null;
    return _extractGoogleAddressParts(results.first);
  }

  Future<LatLng?> _searchLocationWithGoogle(String query) async {
    final attempts = <Map<String, String>>[
      {'address': query, 'language': 'th'},
      {'address': query, 'language': 'en'},
      {'address': query, 'language': 'zh-CN'},
    ];

    for (final params in attempts) {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/geocode/json', <String, String>{
        'address': params['address']!,
        'language': params['language']!,
        'region': 'th',
        'key': _googleMapsApiKey,
      });
      final res = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(ConfigService.requestTimeout);
      if (res.statusCode != 200) continue;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) continue;
      final results = (decoded['results'] is List)
          ? List<Map<String, dynamic>>.from(decoded['results'])
          : const <Map<String, dynamic>>[];
      if (results.isEmpty) continue;

      final location = results.first['geometry']?['location'];
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  Future<void> _resolveAddress() async {
    final requestId = ++_resolveRequestId;
    setState(() => _resolvingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        _selected.latitude,
        _selected.longitude,
      );
      if (!mounted || requestId != _resolveRequestId) return;
      final placemark = placemarks.isNotEmpty ? placemarks.first : null;
      var province = _extractProvince(placemark);
      var district = _extractDistrict(placemark, province);
      var placeName = _extractPlaceName(placemark, district, province);

      if (placeName.isEmpty && province.isEmpty && district.isEmpty) {
        final googleResult = await _reverseGeocodeWithGoogle();
        if (!mounted || requestId != _resolveRequestId) return;
        placeName = (googleResult?['place_name'] ?? '').trim();
        province = (googleResult?['province'] ?? '').trim();
        district = (googleResult?['district'] ?? '').trim();
      }

      setState(() {
        _placeName = placeName;
        _province = province;
        _district = district;
        _resolvingAddress = false;
      });
    } catch (_) {
      try {
        final googleResult = await _reverseGeocodeWithGoogle();
        if (!mounted || requestId != _resolveRequestId) return;
        setState(() {
          _placeName = (googleResult?['place_name'] ?? '').trim();
          _province = (googleResult?['province'] ?? '').trim();
          _district = (googleResult?['district'] ?? '').trim();
          _resolvingAddress = false;
        });
      } catch (_) {
        if (!mounted || requestId != _resolveRequestId) return;
        setState(() {
          _placeName = '';
          _province = '';
          _district = '';
          _resolvingAddress = false;
        });
      }
    }
  }

  Future<void> _searchLocation() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty || _searchingLocation) return;

    FocusScope.of(context).unfocus();
    setState(() => _searchingLocation = true);
    try {
      LatLng? target;
      try {
        final locations = await locationFromAddress(query);
        if (locations.isNotEmpty) {
          final first = locations.first;
          target = LatLng(first.latitude, first.longitude);
        }
      } catch (_) {}

      target ??= await _searchLocationWithGoogle(query);
      if (!mounted) return;
      if (target == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not found')),
        );
        return;
      }

      final LatLng resolvedTarget = target;
      setState(() => _selected = resolvedTarget);
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: resolvedTarget, zoom: 16),
        ),
      );
      await _resolveAddress();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Search failed. Try Thai, English, or Chinese keywords.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _searchingLocation = false);
      }
    }
  }

  Widget _buildWebMapSetupMessage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6EAF2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Google Maps is not configured for Flutter web.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The web app is missing the Google Maps JavaScript API, so the embedded map cannot load.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Fix:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '1. Open gathergo/web/index.html\n'
                    '2. Replace YOUR_GOOGLE_MAPS_API_KEY with a real browser-enabled Maps JavaScript API key\n'
                    '3. Restart flutter run -d chrome',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Current point: ${_selected.latitude.toStringAsFixed(6)}, '
                    '${_selected.longitude.toStringAsFixed(6)}\n'
                    'Place: ${_placeName.isEmpty ? '-' : _placeName}\n'
                    'Province: ${_province.isEmpty ? '-' : _province}\n'
                    'District: ${_district.isEmpty ? '-' : _district}'
                    '${_resolvingAddress ? '\nResolving address...' : ''}',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowWebFallback = kIsWeb && !isGoogleMapsAvailable();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Event Location'),
        actions: [
          TextButton(
            onPressed: _resolvingAddress ? null : _confirmSelection,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (shouldShowWebFallback)
            _buildWebMapSetupMessage()
          else
            GoogleMap(
              onMapCreated: (controller) => _mapController = controller,
              initialCameraPosition: CameraPosition(
                target: _selected,
                zoom: 15,
              ),
              onTap: _setMarker,
              onLongPress: _setMarker,
              markers: {
                Marker(
                  markerId: const MarkerId('event_location'),
                  position: _selected,
                  draggable: true,
                  onDragEnd: _setMarker,
                ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
            ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: SafeArea(
              bottom: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchLocation(),
                          decoration: const InputDecoration(
                            hintText: 'Search place in TH / EN / CN',
                            prefixIcon: Icon(Icons.search),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _searchingLocation ? null : _searchLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(_searchingLocation ? '...' : 'Search'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 88,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Tap the map or drag the marker to set the event location.\n'
                  'Lat: ${_selected.latitude.toStringAsFixed(6)}, '
                  'Lng: ${_selected.longitude.toStringAsFixed(6)}\n'
                  'Place: ${_placeName.isEmpty ? '-' : _placeName}\n'
                  'Province: ${_province.isEmpty ? '-' : _province}\n'
                  'District: ${_district.isEmpty ? '-' : _district}'
                  '${_searchingLocation ? '\nSearching location...' : ''}'
                  '${_resolvingAddress ? '\nResolving address...' : ''}',
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _resolvingAddress ? null : _confirmSelection,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    _resolvingAddress
                        ? 'Resolving location...'
                        : 'Use This Location',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
