import 'package:flutter/material.dart';

class LibraryNavigation extends StatelessWidget {
  const LibraryNavigation({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
    this.onSearchTap,
  });

  final int selectedIndex;
  final List<({String label, IconData icon, IconData selectedIcon})> items;
  final ValueChanged<int> onSelected;
  final VoidCallback? onSearchTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final shadowColor = dark ? const Color(0xff0b0610) : colors.shadow;
    final leftCount = items.length >= 4 ? 2 : items.length ~/ 2;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colors.outlineVariant,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: dark ? .45 : .12),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var index = 0; index < leftCount; index++)
                    Expanded(child: _destination(context, index)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Semantics(
                      button: true,
                      label: 'Search catalog',
                      child: Material(
                        color: colors.primary,
                        shape: const CircleBorder(),
                        elevation: 4,
                        shadowColor: colors.primary.withValues(alpha: .36),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onSearchTap ?? () => onSelected(0),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.search_rounded,
                              color: colors.onPrimary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (var index = leftCount; index < items.length; index++)
                    Expanded(child: _destination(context, index)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _destination(BuildContext context, int index) {
    final item = items[index];
    final selected = index == selectedIndex;
    final colors = Theme.of(context).colorScheme;
    final iconColor = selected
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    final labelColor = selected ? colors.primary : colors.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onSelected(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? colors.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                color: iconColor,
                size: 21,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
