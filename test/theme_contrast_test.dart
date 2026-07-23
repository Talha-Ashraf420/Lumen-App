import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/theme.dart';

void main() {
  test('ships five distinct named accent directions', () {
    expect(accentSchemes, hasLength(5));
    expect(accentSchemes.first.color, defaultAccent);
    expect(accentSchemes.map((scheme) => scheme.color).toSet(), hasLength(5));
    expect(accentPresets, hasLength(5));
  });

  test('every accent has readable fill content and neutral-surface ink', () {
    const samples = <Color>[
      ...accentPresets,
      Color(0xFFFFFFFF),
      Color(0xFF111111),
      Color(0xFF808080),
    ];

    for (final color in samples) {
      for (final palette in [darkPaletteFor(color), lightPaletteFor(color)]) {
        for (final neutral in [
          palette.bg,
          palette.surface,
          palette.surfaceHi,
        ]) {
          expect(
            contrastRatio(palette.muted, neutral),
            greaterThanOrEqualTo(4.5),
            reason: 'Secondary copy must be readable on $neutral.',
          );
          expect(
            contrastRatio(palette.subtle, neutral),
            greaterThanOrEqualTo(4.5),
            reason: 'Tertiary copy must be readable on $neutral.',
          );
        }
        expect(
          contrastRatio(foregroundFor(palette.accent), palette.accent),
          greaterThanOrEqualTo(4.5),
          reason: 'Accent fill ${palette.accent} must have readable content.',
        );
        expect(
          contrastRatio(palette.accentInk, palette.surface),
          greaterThanOrEqualTo(4.5),
          reason:
              'Accent ink ${palette.accentInk} must be readable on ${palette.surface}.',
        );
        expect(
          contrastRatio(palette.accentInk, palette.bg),
          greaterThanOrEqualTo(4.5),
          reason:
              'Accent ink ${palette.accentInk} must be readable on ${palette.bg}.',
        );
        expect(
          contrastRatio(palette.accentInk, palette.surfaceHi),
          greaterThanOrEqualTo(4.5),
          reason:
              'Accent ink ${palette.accentInk} must be readable on ${palette.surfaceHi}.',
        );
      }
    }
  });
}
