import 'package:flutter/material.dart';

import 'strings.dart';
import 'theme_profile.dart';

ColorScheme _violetScheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final brand = dark ? const Color(0xffc3adff) : const Color(0xff5e3cba);
  final page = dark ? const Color(0xff181326) : const Color(0xfff8f6ff);
  final panel = dark ? const Color(0xff241b37) : Colors.white;
  final border = dark ? const Color(0xff504467) : const Color(0xffe3dcef);
  final text = dark ? const Color(0xffede5fb) : const Color(0xff261b3e);
  final muted = dark ? const Color(0xffccbfdd) : const Color(0xff5d5074);
  return ColorScheme.fromSeed(seedColor: brand, brightness: brightness)
      .copyWith(
        primary: brand,
        onPrimary: dark ? const Color(0xff271648) : Colors.white,
        primaryContainer: dark ? const Color(0xff40305d) : const Color(0xffece4ff),
        onPrimaryContainer: dark ? const Color(0xfff3e5ff) : const Color(0xff432887),
        surface: page,
        onSurface: text,
        onSurfaceVariant: muted,
        surfaceContainerLow: panel,
        surfaceContainer: dark ? const Color(0xff2d2243) : const Color(0xfff2edff),
        surfaceContainerHighest: dark ? const Color(0xff45365e) : const Color(0xffeae1fa),
        outline: muted,
        outlineVariant: border,
        tertiary: dark ? const Color(0xffefc688) : const Color(0xff765317),
        tertiaryContainer: dark ? const Color(0xff523e21) : const Color(0xfffbefd7),
        onTertiaryContainer: dark ? const Color(0xffffdfac) : const Color(0xff5b4216),
      );
}

ThemeData boiPathTheme(Brightness brightness, [ThemeProfile profile = ThemeProfile.violet]) {
  final dark = brightness == Brightness.dark;
  final scheme = profile == ThemeProfile.violet
      ? _violetScheme(brightness)
      : ColorScheme.fromSeed(seedColor: profile.seed, brightness: brightness);
  final brand = scheme.primary;
  final page = scheme.surface;
  final panel = scheme.surfaceContainerLow;
  final border = scheme.outlineVariant;
  final text = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final type = base.textTheme.apply(bodyColor: text, displayColor: text);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(23));
  return base.copyWith(
    scaffoldBackgroundColor: page,
    textTheme: type.copyWith(
      displaySmall: type.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1.14),
      headlineMedium: type.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.17),
      headlineSmall: type.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.23),
      titleLarge: type.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
      titleMedium: type.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.36),
      bodyMedium: type.bodyMedium?.copyWith(height: 1.48),
    ),
    appBarTheme: AppBarThemeData(backgroundColor: panel, surfaceTintColor: Colors.transparent,
      foregroundColor: text, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(color: panel, elevation: 1, margin: EdgeInsets.zero,
      shadowColor: brand.withValues(alpha: dark ? .10 : .16),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23), side: BorderSide(color: border))),
    dialogTheme: DialogThemeData(backgroundColor: panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: panel, indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      selectedIconTheme: IconThemeData(color: brand),
      unselectedIconTheme: IconThemeData(color: muted),
      selectedLabelTextStyle: TextStyle(color: text, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: muted, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      shape: shape, minimumSize: const Size(48, 48), textStyle: const TextStyle(fontWeight: FontWeight.w700),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      shape: shape, minimumSize: const Size(48, 48), side: BorderSide(color: border),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      shape: shape, minimumSize: const Size(44, 44), textStyle: const TextStyle(fontWeight: FontWeight.w700),
    )),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true, fillColor: panel,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: brand, width: 2)),
    ),
    dividerTheme: DividerThemeData(color: border),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, required this.words, this.showName = true});
  final Words words;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [colors.primary, Color.lerp(colors.primary, colors.onSurface, .20)!]),
          borderRadius: BorderRadius.circular(13)),
        child: Icon(Icons.auto_stories_rounded, size: 22, color: colors.onPrimary)),
      if (showName) ...[
        const SizedBox(width: 10),
        Text(words('BoiPath'), style: Theme.of(context).textTheme.titleLarge),
      ],
    ]);
  }
}

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child));
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.icon, required this.title, this.detail, this.action});
  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfacePanel(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 56, height: 56,
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(17)),
            child: Icon(icon, color: theme.colorScheme.primary)),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]))));
  }
}

class BookStatus extends StatelessWidget {
  const BookStatus({super.key, required this.status, required this.words, this.downloaded = false});
  final String status;
  final Words words;
  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, background, ink) = switch ((downloaded, status)) {
      (true, _) => (Icons.download_done_rounded, scheme.primaryContainer, scheme.onPrimaryContainer),
      (_, 'linked') => (Icons.download_rounded, scheme.primaryContainer, scheme.onPrimaryContainer),
      (_, 'verified') => (Icons.check_circle_outline_rounded, scheme.primaryContainer, scheme.onPrimaryContainer),
      (_, 'pending') => (Icons.schedule_rounded, scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (Icons.info_outline_rounded, scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: ink),
        const SizedBox(width: 5),
        Flexible(child: Text(downloaded ? words('Downloaded') : words.status(status),
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
