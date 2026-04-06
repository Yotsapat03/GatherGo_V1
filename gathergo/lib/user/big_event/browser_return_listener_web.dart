// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/widgets.dart';

class BrowserReturnListener {
  VoidCallback? _onReturn;
  html.EventListener? _focusListener;
  html.EventListener? _visibilityListener;

  void attach(VoidCallback onReturn) {
    _onReturn = onReturn;
    _focusListener = (_) => _notifyReturn('focus');
    _visibilityListener = (_) {
      if (html.document.visibilityState == 'visible') {
        _notifyReturn('visibility');
      }
    };
    html.window.addEventListener('focus', _focusListener);
    html.document.addEventListener('visibilitychange', _visibilityListener);
  }

  void dispose() {
    if (_focusListener != null) {
      html.window.removeEventListener('focus', _focusListener);
    }
    if (_visibilityListener != null) {
      html.document
          .removeEventListener('visibilitychange', _visibilityListener);
    }
    _onReturn = null;
    _focusListener = null;
    _visibilityListener = null;
  }

  void _notifyReturn(String source) {
    debugPrint('[StripePaymentUI] browser-return source=$source');
    _onReturn?.call();
  }
}
