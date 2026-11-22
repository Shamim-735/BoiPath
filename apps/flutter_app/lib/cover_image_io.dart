import 'package:flutter/material.dart';

class CoverImage extends StatefulWidget {
  const CoverImage({super.key, required this.urls});

  final List<String> urls;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.urls.length) return const SizedBox.shrink();
    final url = widget.urls[_index];
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
      errorBuilder: (_, __, ___) {
        if (_index + 1 < widget.urls.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _index++);
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}
