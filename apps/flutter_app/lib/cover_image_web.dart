import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: HtmlElementView.fromTagName(
        tagName: 'img',
        onElementCreated: (Object element) {
          final img = element as web.HTMLImageElement;
          img.src = url;
          img.referrerPolicy = 'no-referrer';
          img.style
            ..width = '100%'
            ..height = '100%'
            ..objectFit = 'cover'
            ..display = 'block'
            ..pointerEvents = 'none';
          img.onerror = ((web.Event _) {
            img.style.display = 'none';
          }).toJS;
        },
      ),
    );
  }
}
