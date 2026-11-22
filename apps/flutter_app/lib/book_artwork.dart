import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book.dart';
import 'cover_image.dart';

/// Draws the same illustration for a title on the shelf and on its detail page.
class BookArtwork extends StatelessWidget {
  const BookArtwork({super.key, required this.book, this.compact = false});

  final Book book;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (symbol, tint) = _subjectArtwork[book.subject] ??
        (Icons.auto_stories_rounded, const Color(0xff9072ca));
    final seed = _illustrationSeed(book.id);
    final accent = Color.lerp(tint, const Color(0xffa693f2), ((seed >> 8) & 15) / 32)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final first = Color.lerp(
      dark ? const Color(0xff211630) : const Color(0xfffcf8ff),
      accent,
      .12,
    )!;
    final last = Color.lerp(
      dark ? const Color(0xff312044) : const Color(0xfff3ecff),
      accent,
      dark ? .30 : .24,
    )!;

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [first, last],
          ),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final height = math.min(constraints.maxHeight * .76, constraints.maxWidth * 1.08);
          final width = height * .75;
          final tilt = ((seed & 7) - 3.5) * .024;
          final corner = BorderRadius.circular(width * .10);
          final coverTop = Color.lerp(accent, const Color(0xff43216c), .33)!;
          final coverBottom = Color.lerp(accent, const Color(0xff2c194d), .68)!;
          final coverUrls = book.resolvedCoverUrls;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (!compact)
                CustomPaint(painter: _ArtworkSurround(accent: accent, seed: seed)),
              Center(
                child: Transform.rotate(
                  angle: tilt,
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: corner,
                      boxShadow: [
                        BoxShadow(
                          color: coverBottom.withValues(alpha: .34),
                          offset: Offset(0, height * .074),
                          blurRadius: height * .14,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: corner,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [coverTop, coverBottom],
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(painter: _CoverPattern(accent: accent, seed: seed)),
                            Align(
                              alignment: const Alignment(.09, -.07),
                              child: Icon(
                                _titleSymbol(book, symbol),
                                color: const Color(0xfffff5ff),
                                size: width * (compact ? .52 : .44),
                              ),
                            ),
                        if (coverUrls.isNotEmpty)
                         CoverImage(key: ValueKey<String>(coverUrls.first), urls: coverUrls),
                      Image.asset('assets/covers/${book.id}.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 6,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.black.withValues(alpha: .08),
                                    Colors.black.withValues(alpha: .06),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: corner,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .16),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                            ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

const _subjectArtwork = <String, (IconData, Color)>{
  'accounting': (Icons.calculate_outlined, Color(0xff797abf)),
  'agriculture': (Icons.grass_rounded, Color(0xff649887)),
  'arabic': (Icons.translate_rounded, Color(0xff9980c1)),
  'arts-crafts': (Icons.palette_outlined, Color(0xffc477a6)),
  'bangla': (Icons.auto_stories_rounded, Color(0xffa474ca)),
  'bangladesh-global-studies': (Icons.public_rounded, Color(0xff6e90c9)),
  'biology': (Icons.biotech_rounded, Color(0xff6a9b91)),
  'buddhism': (Icons.temple_buddhist_rounded, Color(0xffb59072)),
  'career-education': (Icons.work_outline_rounded, Color(0xff8578cb)),
  'chemistry': (Icons.science_outlined, Color(0xff8b76d2)),
  'christianity': (Icons.church_rounded, Color(0xffa886c8)),
  'civics': (Icons.groups_outlined, Color(0xff7b85c7)),
  'economics': (Icons.show_chart_rounded, Color(0xff7588c5)),
  'english': (Icons.forum_outlined, Color(0xff8678d7)),
  'entrepreneurship': (Icons.lightbulb_outline_rounded, Color(0xffb28a6d)),
  'finance-banking': (Icons.account_balance_rounded, Color(0xff6f92ba)),
  'geography': (Icons.terrain_rounded, Color(0xff6c9e9d)),
  'higher-mathematics': (Icons.functions_rounded, Color(0xff8f75cd)),
  'hinduism': (Icons.temple_hindu_rounded, Color(0xffbd8a84)),
  'history': (Icons.history_edu_rounded, Color(0xffaf869e)),
  'home-science': (Icons.home_outlined, Color(0xffb386ac)),
  'ict': (Icons.memory_rounded, Color(0xff787be0)),
  'islam': (Icons.mosque_rounded, Color(0xff739688)),
  'mathematics': (Icons.calculate_rounded, Color(0xffa874c6)),
  'music': (Icons.music_note_rounded, Color(0xffbf81ae)),
  'pali': (Icons.menu_book_rounded, Color(0xffa183ae)),
  'physical-education': (Icons.directions_run_rounded, Color(0xffa875b7)),
  'physics': (Icons.electric_bolt_rounded, Color(0xff727fd1)),
  'sanskrit': (Icons.history_edu_rounded, Color(0xffa686b6)),
  'science': (Icons.science_rounded, Color(0xff7a88d1)),
  'work-life-education': (Icons.handyman_outlined, Color(0xff917bb5)),
};

IconData _titleSymbol(Book book, IconData subjectSymbol) {
  final title = book.title.toLowerCase();
  if (title.contains('ব্যাকরণ') || title.contains('grammar')) return Icons.edit_note_rounded;
  if (title.contains('সাহিত্য') || title.contains('literature')) return Icons.history_edu_rounded;
  if (title.contains('সহপাঠ') || title.contains('দ্রুত পঠন')) return Icons.bookmarks_outlined;
  return subjectSymbol;
}

// Keep the arithmetic within the exact integer range of both Dart VM and web.
int _illustrationSeed(String id) {
  var seed = 0;
  for (final unit in id.codeUnits) {
    seed = (seed * 31 + unit) & 0x7fffffff;
  }
  return seed;
}

class _ArtworkSurround extends CustomPainter {
  const _ArtworkSurround({required this.accent, required this.seed});

  final Color accent;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    final center = size.center(Offset.zero);
    final paint = Paint()..color = accent.withValues(alpha: .13);
    canvas.drawCircle(center, unit * .42, paint);
    paint
      ..color = accent.withValues(alpha: .30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(Rect.fromCenter(center: center, width: unit * 1.17, height: unit * .69), paint);

    paint.style = PaintingStyle.fill;
    for (var index = 0; index < 6; index++) {
      final bits = (seed >> (index * 4)) & 15;
      final x = (.45 + index % 3 * .12) * unit * (index.isEven ? 1 : -1);
      final y = ((bits / 15) - .5) * unit * .64;
      final point = center + Offset(x, y);
      final radius = (index.isEven ? .030 : .015) * unit;
      final spark = Path()
        ..moveTo(point.dx, point.dy - radius)
        ..quadraticBezierTo(point.dx + radius * .2, point.dy - radius * .2, point.dx + radius, point.dy)
        ..quadraticBezierTo(point.dx + radius * .2, point.dy + radius * .2, point.dx, point.dy + radius)
        ..quadraticBezierTo(point.dx - radius * .2, point.dy + radius * .2, point.dx - radius, point.dy)
        ..quadraticBezierTo(point.dx - radius * .2, point.dy - radius * .2, point.dx, point.dy - radius)
        ..close();
      canvas.drawPath(spark, paint);
    }
  }

  @override
  bool shouldRepaint(_ArtworkSurround old) => old.accent != accent || old.seed != seed;
}

class _CoverPattern extends CustomPainter {
  const _CoverPattern({required this.accent, required this.seed});

  final Color accent;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final paint = Paint()..color = const Color(0xff211335).withValues(alpha: .27);
    canvas.drawRect(Rect.fromLTWH(0, 0, width * .10, height), paint);
    paint
      ..color = Colors.white.withValues(alpha: .27)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(width * .11, 0), Offset(width * .11, height), paint);

    final focus = Offset(width * .55, height * .47);
    paint.color = accent.withValues(alpha: .38);
    canvas.drawCircle(focus, width * .33, paint);
    paint
      ..style = PaintingStyle.stroke
      ..color = const Color(0xffffeaff).withValues(alpha: .33);
    final offset = ((seed >> 4) & 7) / 14;
    for (var index = 0; index < 3; index++) {
      final radius = width * (.40 + index * .077);
      switch ((seed >> 12) % 3) {
        case 0:
          canvas.drawArc(
            Rect.fromCircle(center: focus, radius: radius),
            (offset + index * .25) * math.pi,
            1.42 * math.pi,
            false,
            paint,
          );
        case 1:
          canvas.drawPath(Path()
            ..moveTo(focus.dx - radius, focus.dy)
            ..lineTo(focus.dx + width * offset * .2, focus.dy - radius)
            ..lineTo(focus.dx + radius, focus.dy)
            ..lineTo(focus.dx - width * offset * .2, focus.dy + radius)
            ..close(), paint);
        case 2:
          final y = focus.dy + (index - 1) * height * .23;
          canvas.drawPath(Path()
            ..moveTo(width * .11, y)
            ..cubicTo(width * .34, y - radius * .6, width * .63, y + radius * .6, width, y), paint);
      }
    }

    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xffffeaff).withValues(alpha: .70);
    for (var index = 0; index < 4; index++) {
      final mark = ((seed >> (index * 5)) & 31) / 31;
      canvas.drawCircle(
        Offset(width * (.29 + index * .15), height * (.83 + mark * .07)),
        width * (.011 + mark * .012),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CoverPattern old) => old.accent != accent || old.seed != seed;
}
