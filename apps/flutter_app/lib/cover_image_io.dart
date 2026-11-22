import 'package:flutter/material.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
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
