import 'package:flutter/material.dart';

enum ThemeProfile {
  violet('Violet', Color(0xff5e3cba)),
  ocean('Ocean', Color(0xff2468a4)),
  teal('Teal', Color(0xff157869)),
  forest('Forest', Color(0xff417347)),
  rose('Rose', Color(0xffa53e6e)),
  amber('Amber', Color(0xff965b14));

  const ThemeProfile(this.label, this.seed);

  final String label;
  final Color seed;

  static ThemeProfile restore(String? key) =>
      values.firstWhere((profile) => profile.name == key, orElse: () => violet);
}
