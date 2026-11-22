import 'dart:math' as math;

import 'package:flutter/material.dart';

class LibraryNavigation extends StatelessWidget {
  const LibraryNavigation({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<({String label, IconData icon, IconData selectedIcon})> items;
  final ValueChanged<int> onSelected;

  static const _medallionSize = 44.0;
  static const _surfaceTop = 19.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final labelHeight = math.max(23.0, MediaQuery.textScalerOf(context).scale(11) * 2.6);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 340);
    final shadow = dark ? const Color(0xff100916) : colors.primary;

    final direction = Directionality.of(context);
    final visualIndex = (direction == TextDirection.ltr
        ? selectedIndex : items.length - 1 - selectedIndex).toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SizedBox(
              width: double.infinity,
              height: 55 + labelHeight + 7,
              child: LayoutBuilder(builder: (context, bounds) {
                final slotWidth = bounds.maxWidth / items.length;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: visualIndex, end: visualIndex),
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < items.length; index++)
                        Expanded(child: _destination(context, index, labelHeight: labelHeight,
                          duration: duration)),
                    ],
                  ),
                  builder: (context, position, destinations) {
                    final center = (position + .5) * slotWidth;
                    return Stack(fit: StackFit.expand, children: [
                      CustomPaint(painter: _NavigationSurface(
                        centerX: center,
                        top: _surfaceTop,
                        diameter: _medallionSize + 10,
                        start: colors.surfaceContainerLow,
                        end: Color.lerp(colors.surfaceContainerLow, colors.primaryContainer, .32)!,
                        border: colors.outlineVariant,
                        shadow: shadow.withValues(alpha: dark ? .55 : .23),
                      )),
                      destinations!,
                    if (!(items.length == 5 && selectedIndex == 2))   Positioned(
                        left: center - _medallionSize / 2,
                        top: 0,
                        child: IgnorePointer(child: ExcludeSemantics(child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [colors.primary, Color.lerp(colors.primary, colors.onSurface, .14)!],
                            ),
                            border: Border.all(color: colors.outlineVariant),
                            boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: .32),
                              blurRadius: 10, offset: const Offset(0, 3))],
                          ),
                          child: SizedBox.square(
                            dimension: _medallionSize,
                            child: AnimatedSwitcher(
                              duration: duration == Duration.zero ? Duration.zero : const Duration(milliseconds: 160),
                              transitionBuilder: (child, animation) => FadeTransition(opacity: animation,
                                child: ScaleTransition(scale: Tween<double>(begin: .78, end: 1).animate(animation),
                                  child: child)),
                              child: Icon(items[selectedIndex].selectedIcon, key: ValueKey(selectedIndex),
                                color: colors.onPrimary, size: 22),
                            ),
                          ),
                        ))),
                      ),
                    ]);
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context,
    int index, {
    required double labelHeight,
    required Duration duration,
  }) {
    final item = items[index];
    final selected = selectedIndex == index;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activate = () => onSelected(index);

       if (items.length == 5 && index == 2) {
      return Semantics(
        container: true,
        label: item.label,
        button: true,
        selected: selected,
        onTap: activate,
        child: Tooltip(
          message: item.label,
          child: Center(
            child: InkResponse(
              onTap: activate,
              customBorder: const CircleBorder(),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7B4DFF), Color(0xFF4B1FA6)],
                  ),
                  border: selected
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 1.5,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B4DFF).withValues(alpha: 0.45),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: item.label,
      button: true,
      selected: selected,
      onTap: activate,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: activate,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(22),
          focusColor: colors.primary.withValues(alpha: .16),
          hoverColor: colors.primary.withValues(alpha: .07),
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: 25,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: selected ? 0 : 1,
                    duration: duration,
                    child: Icon(item.icon, size: 21, color: colors.onSurfaceVariant),
                  ),
                ),
                Positioned(
                  top: 55,
                  left: 2,
                  right: 2,
                  height: labelHeight,
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      height: 1.24,
                      color: selected ? colors.primary : colors.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationSurface extends CustomPainter {
  const _NavigationSurface({
    required this.centerX,
    required this.top,
    required this.diameter,
    required this.start,
    required this.end,
    required this.border,
    required this.shadow,
  });

  final double centerX;
  final double top;
  final double diameter;
  final Color start;
  final Color end;
  final Color border;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final host = Rect.fromLTRB(.5, top, size.width - .5, size.height - .5);
    final guest = Rect.fromCircle(center: Offset(centerX, LibraryNavigation._medallionSize / 2),
      radius: diameter / 2);
    final notch = const CircularNotchedRectangle().getOuterPath(host, guest);
    final rounded = Path()..addRRect(RRect.fromRectAndRadius(host, const Radius.circular(25)));
    final surface = Path.combine(PathOperation.intersect, rounded, notch);
    canvas.drawShadow(surface, shadow, 10, false);
    canvas.drawPath(surface, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [start, end],
    ).createShader(host));
    canvas.drawPath(surface, Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_NavigationSurface old) =>
      old.centerX != centerX ||
      old.top != top || old.diameter != diameter || old.start != start || old.end != end ||
      old.border != border || old.shadow != shadow;
}
