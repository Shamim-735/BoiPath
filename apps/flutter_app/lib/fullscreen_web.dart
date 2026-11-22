import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> setPlatformFullscreen(bool enabled) async {
  try {
    if (enabled && web.document.fullscreenElement == null) {
      await web.document.documentElement?.requestFullscreen().toDart;
    } else if (!enabled && web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (_) {
    // Keep the in-app presentation active when the browser rejects full screen.
  }
}
