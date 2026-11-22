import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: HtmlElementView.fromTagName(
        key: ValueKey<String>(urls.join('|')),
        tagName: 'img',
        onElementCreated: (Object element) {
          final img = element as web.HTMLImageElement;
          img.referrerPolicy = 'no-referrer';
         img.loading = 'lazy';
          img.decoding = 'async';
          img.style
            ..width = '100%'
            ..height = '100%'
            ..objectFit = 'cover'
            ..objectPosition = 'top center'
            ..display = 'block'
            ..pointerEvents = 'none';

          var attempt = 0;
          var retriedFirst = false;
          img.onerror = ((web.Event _) {
            attempt += 1;
            if (attempt < urls.length) {
              Timer(Duration(milliseconds: 600 + attempt * 400), () { img.src = urls[attempt]; });
            } else if (!retriedFirst) {
              retriedFirst = true;
              Timer(const Duration(milliseconds: 2200), () { img.src = urls.first; });
            } else {
              img.style.display = 'none';
            }
          }).toJS;

          img.src = urls.first;
        },
      ),
    );
  }
}
