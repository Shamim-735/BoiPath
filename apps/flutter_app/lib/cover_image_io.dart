import 'package:flutter/material.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      key: ValueKey<String>(url),
      alignment: Alignment.topCenter,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      frameBuilder: (context, child, frame, wasSync) => AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: child,
      ),
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
