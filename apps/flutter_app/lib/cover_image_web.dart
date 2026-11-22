import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class _CoverLoadQueue {
  static const int _maxConcurrent = 3;
  static int _active = 0;
  static final Queue<void Function()> _pending = Queue<void Function()>();

  static void enqueue(void Function() task) {
    if (_active < _maxConcurrent) {
      _active++;
      task();
    } else {
      _pending.addLast(task);
    }
  }

  static void release() {
    if (_pending.isNotEmpty) {
      final next = _pending.removeFirst();
      next();
    } else if (_active > 0) {
      _active--;
    }
  }
}

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
          img.decoding = 'async';
          img.style
            ..width = '100%'
            ..height = '100%'
            ..objectFit = 'cover'
            ..objectPosition = 'top center'
            ..display = 'block'
            ..pointerEvents = 'none'
            ..opacity = '0'
            ..transition = 'opacity 200ms ease';

          var attempt = 0;
          var retriedFirst = false;
          var slotActive = false;

          void loadCurrent() {
            final targetUrl = attempt < urls.length ? urls[attempt] : urls[0];
            _CoverLoadQueue.enqueue(() {
              slotActive = true;
              img.src = targetUrl;
            });
          }

          img.onload = ((web.Event _) {
            if (slotActive) {
              slotActive = false;
              _CoverLoadQueue.release();
            }
            img.style.opacity = '1';
          }).toJS;

          img.onerror = ((web.Event _) {
            if (slotActive) {
              slotActive = false;
              _CoverLoadQueue.release();
            }
            attempt += 1;
            if (attempt < urls.length) {
              Timer(Duration(milliseconds: 500 + attempt * 400), loadCurrent);
            } else if (!retriedFirst) {
              retriedFirst = true;
              Timer(const Duration(seconds: 2), loadCurrent);
            } else {
              img.style.display = 'none';
            }
          }).toJS;

          loadCurrent();
        },
      ),
    );
  }
}
