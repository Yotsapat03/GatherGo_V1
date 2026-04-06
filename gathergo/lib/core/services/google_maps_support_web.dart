import 'dart:js_util' as js_util;

bool isGoogleMapsAvailableImpl() {
  final google = js_util.getProperty<Object?>(js_util.globalThis, 'google');
  if (google == null) return false;

  final maps = js_util.getProperty<Object?>(google, 'maps');
  return maps != null;
}
