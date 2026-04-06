import 'package:url_launcher/url_launcher.dart';

class SpotMapLauncher {
  static double? parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static Uri? buildMapsUri({
    dynamic latitude,
    dynamic longitude,
    dynamic locationText,
  }) {
    final lat = parseCoordinate(latitude);
    final lng = parseCoordinate(longitude);
    if (lat != null && lng != null) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
    }

    final location = (locationText ?? '').toString().trim();
    if (location.isEmpty) return null;

    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': location,
    });
  }

  static Future<bool> open({
    dynamic latitude,
    dynamic longitude,
    dynamic locationText,
  }) async {
    final uri = buildMapsUri(
      latitude: latitude,
      longitude: longitude,
      locationText: locationText,
    );
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
