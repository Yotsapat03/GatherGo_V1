import 'google_maps_support_stub.dart'
    if (dart.library.js_interop) 'google_maps_support_web.dart';

bool isGoogleMapsAvailable() => isGoogleMapsAvailableImpl();
