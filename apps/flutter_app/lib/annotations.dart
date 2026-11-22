import 'dart:convert';

import 'package:flutter/material.dart';

import 'store.dart';

enum InkTool { pan, pen, highlight, erase }

class LessonInk extends ChangeNotifier {
  LessonInk(this.store, this.bookId) {
    final stored = jsonDecode(store.storedText('ink:$bookId') ?? '{}') as Map;
    for (final entry in stored.entries) {
      pages[int.parse(entry.key as String)] = (entry.value as List)
          .map((value) => Stroke.fromJson(value as Map)).toList();
    }
  }

  final LibraryStore store;
  final String bookId;
  final pages = <int, List<Stroke>>{};
  final undoStack = <int, List<List<Stroke>>>{};
  final redoStack = <int, List<List<Stroke>>>{};
  InkTool tool = InkTool.pan;
  Color color = const Color(0xff325bcc);
  double width = 4;
  bool visible = true;

  List<Stroke> page(int n) => pages.putIfAbsent(n, () => []);

  void snapshot(int n) {
    final history = undoStack.putIfAbsent(n, () => []);
    history.add(List.of(page(n)));
    if (history.length > 40) history.removeAt(0);
    redoStack[n]?.clear();
  }

  void undo(int n) => _restore(n, undoStack, redoStack);
  void redo(int n) => _restore(n, redoStack, undoStack);

  void _restore(int n, Map<int, List<List<Stroke>>> source, Map<int, List<List<Stroke>>> target) {
    final history = source[n];
    if (history == null || history.isEmpty) return;
    target.putIfAbsent(n, () => []).add(List.of(page(n)));
    pages[n] = history.removeLast();
    save();
  }

  Map<String, dynamic> toJson() => pages.map((key, value) =>
      MapEntry('$key', value.map((stroke) => stroke.toJson()).toList()));

  void save() {
    store.setText('ink:$bookId', jsonEncode(toJson()));
    changed();
  }

  void changed() => notifyListeners();
}

class Stroke {
  const Stroke(this.points, this.color, this.relativeWidth);
  final List<Offset> points;
  final Color color;
  final double relativeWidth;

  Stroke.fromJson(Map data)
    : points = (data['points'] as List).map((pair) {
        final xy = pair as List;
        return Offset((xy[0] as num).toDouble(), (xy[1] as num).toDouble());
      }).toList(),
      color = Color(data['color'] as int),
      relativeWidth = (data['width'] as num).toDouble();

  Map<String, Object> toJson() => {
    'color': color.toARGB32(), 'width': relativeWidth,
    'points': [for (final p in points) [p.dx, p.dy]],
  };
}

class PageInk extends StatefulWidget {
  const PageInk({super.key, required this.ink, required this.page});
  final LessonInk ink;
  final int page;

  @override
  State<PageInk> createState() => _PageInkState();
}

class _PageInkState extends State<PageInk> {
  Stroke? working;
  int? pointer;

  Offset normalize(Offset point, Size size) => Offset(
      (point.dx / size.width).clamp(0, 1).toDouble(),
      (point.dy / size.height).clamp(0, 1).toDouble());

  void erase(Offset at, Size size) {
    widget.ink.page(widget.page).removeWhere((stroke) =>
      stroke.points.any((p) => (Offset(p.dx * size.width, p.dy * size.height) - at).distance < 15));
    widget.ink.changed();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.ink,
    builder: (_, _) => LayoutBuilder(builder: (_, constraints) {
      final ink = widget.ink;
      final size = constraints.biggest;
      if (!ink.visible || size.isEmpty) return const SizedBox.expand();
      final paint = CustomPaint(painter: InkPainter([...ink.page(widget.page), if (working case final Stroke s) s]),
        child: const SizedBox.expand());
      return ink.tool == InkTool.pan ? IgnorePointer(child: paint) : Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (pointer != null) return;
          pointer = event.pointer;
          ink.snapshot(widget.page);
          if (ink.tool == InkTool.erase) {
            erase(event.localPosition, size);
            return;
          }
          final highlight = ink.tool == InkTool.highlight;
          setState(() => working = Stroke([normalize(event.localPosition, size)],
            highlight ? ink.color.withValues(alpha: .35) : ink.color,
            ink.width * (highlight ? 3 : 1) / size.width));
        },
        onPointerMove: (event) {
          if (pointer != event.pointer) return;
          if (working == null) {
            erase(event.localPosition, size);
          } else {
            setState(() => working!.points.add(normalize(event.localPosition, size)));
          }
        },
        onPointerUp: (event) => finish(event.pointer),
        onPointerCancel: (event) => finish(event.pointer),
        child: paint,
      );
    }),
  );

  void finish(int id) {
    if (pointer != id) return;
    pointer = null;
    if (working case final Stroke stroke) {
      widget.ink.page(widget.page).add(stroke);
      setState(() => working = null);
    }
    widget.ink.save();
  }
}

class InkPainter extends CustomPainter {
  InkPainter(this.strokes);
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final stroke in strokes) {
      final points = stroke.points.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
      if (points.isEmpty) continue;
      final pen = Paint()..color = stroke.color
        ..strokeWidth = stroke.relativeWidth * size.width
        ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
      if (points.length == 1) {
        canvas.drawCircle(points.first, pen.strokeWidth / 2, pen);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, pen..style = PaintingStyle.stroke);
      }
    }
  }

  @override
  bool shouldRepaint(InkPainter oldDelegate) => true;
}
