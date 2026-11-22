import 'package:flutter/material.dart';

class LibraryQuickAction extends StatelessWidget {
  const LibraryQuickAction({
    super.key, required this.icon, required this.title, required this.detail,
    required this.onTap, this.emphasized = false,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: emphasized ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(
              color: emphasized ? scheme.surfaceContainerLow : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 21, color: scheme.primary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: scheme.primary),
        ])),
      ),
    );
  }
}
