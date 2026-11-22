import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: HtmlElementView.fromTagName(
        key: ValueKey<String>(urls.join('|')),
        tagName: 'img',
        onElementCreated: (Object element) {
          final img = element as web.HTMLImageElement;
          var attempt = 0; img.src = urls[0]; img.loading = 'lazy'; img.decoding = 'async';
          img.referrerPolicy = 'no-referrer';
          img.style
            ..width = '100%'
            ..height = '100%'
            ..objectFit = 'cover'
            ..objectPosition = 'top center'
            ..display = 'block'
            ..pointerEvents = 'none';
          img.onerror = ((web.Event _) {
            attempt += 1; if (attempt < urls.length) { img.src = urls[attempt]; } else { img.style.display = 'none'; }
          }).toJS;
        },
      ),
    );
  }
}
