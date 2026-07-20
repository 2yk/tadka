/// "Midnight Bazaar" design tokens.
///
/// Ported from web/asset-pack/DESIGN-SYSTEM.md and the web build's CSS custom properties.
/// The family colours are LOCKED — they're baked into game logic and the asset pack, so
/// changing one here desynchronises the art.
///
/// Type: the design calls for Fraunces (display) + Inter (UI). Those aren't bundled yet, so
/// this falls back to a platform serif/sans pair exactly as the web build does under a strict
/// CSP. Bundling the TTFs is a follow-up — deliberately not a network fetch, because the game
/// must render correctly with no connection.
library;

import 'package:flutter/material.dart';

abstract final class T {
  // surfaces
  static const bg = Color(0xFF171426);
  static const panel = Color(0xFF241F38);
  static const panel2 = Color(0xFF2E2846);
  static const line = Color(0xFF38315C);

  // text + accents
  static const ink = Color(0xFFF2E8D5);
  static const dim = Color(0xFF9A92B0);
  static const brass = Color(0xFFD9A441);
  static const brassDark = Color(0xFFA87A2B);
  static const brassLight = Color(0xFFF0C36A);
  static const good = Color(0xFF8FBF6B);
  static const bad = Color(0xFFE85A4F);

  // card faces
  static const parch = Color(0xFFF5E9D0);
  static const parchDark = Color(0xFFE7D6B4);
  static const cream = Color(0xFFFFF6E3);
  static const inkDark = Color(0xFF2B2438);

  // flavour families (LOCKED — mirrored in game logic and asset-pack)
  static const spicy = Color(0xFFE23B22);
  static const sweet = Color(0xFFE8A020);
  static const sour = Color(0xFF7CB342);
  static const salty = Color(0xFF4A90D9);
  static const umami = Color(0xFF8E5AA8);

  static const spicyDark = Color(0xFFA32612);
  static const sweetDark = Color(0xFFB0740E);
  static const sourDark = Color(0xFF557F2B);
  static const saltyDark = Color(0xFF2F639C);
  static const umamiDark = Color(0xFF623A78);

  // rarity rings
  static const common = Color(0xFF8A8494);
  static const uncommon = Color(0xFF7CB342);
  static const rare = Color(0xFFD9A441);

  static const Map<String, Color> family = {
    'spicy': spicy, 'sweet': sweet, 'sour': sour, 'salty': salty, 'umami': umami,
  };
  static const Map<String, Color> familyDark = {
    'spicy': spicyDark, 'sweet': sweetDark, 'sour': sourDark,
    'salty': saltyDark, 'umami': umamiDark,
  };
  static const Map<String, String> familyEmoji = {
    'spicy': '🌶️', 'sweet': '🍯', 'sour': '🍋', 'salty': '🧂', 'umami': '🍄',
  };

  static Color rarityColor(String rarity) => switch (rarity) {
    'uncommon' => uncommon,
    'rare' => rare,
    'festival' => brass,
    'blend' => umami,
    _ => common,
  };

  /// Display face — city names, rank numerals, dish names, the score.
  static const display = 'serif';

  static TextStyle score(double size) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: brass,
    height: 1.0,
  );

  static TextStyle dish(double size, {Color color = ink}) => TextStyle(
    fontFamily: display,
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.1,
  );

  /// UPPERCASE micro-label, letter-spaced — the design system's label treatment.
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: dim,
  );

  static const body = TextStyle(fontSize: 14, color: ink, height: 1.35);
  static const bodyDim = TextStyle(fontSize: 13, color: dim, height: 1.35);

  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      surface: bg,
      primary: brass,
      secondary: umami,
      error: bad,
    ),
    fontFamily: null,
  );
}

/// Motion constants from DESIGN-SYSTEM.md §Motion, in one place so the juice stays coherent.
abstract final class Motion {
  /// Score count-up.
  static const countUp = Duration(milliseconds: 700);
  static const countUpCurve = Curves.easeOutExpo;

  /// Card trigger wobble.
  static const wobble = Duration(milliseconds: 90);
  static const wobbleDegrees = 4.0;

  /// Particle burst per triggered card.
  static const burst = Duration(milliseconds: 400);
  static const burstMin = 6;
  static const burstMax = 10;

  /// Screen shake scales with the multiplier: 3px base, +1px per extra multiple, cap 8px.
  static const shake = Duration(milliseconds: 120);
  static double shakePixels(double multiplier) =>
      (3.0 + (multiplier - 2.0).clamp(0.0, double.infinity)).clamp(3.0, 8.0);

  static const deal = Duration(milliseconds: 260);
  static const dealStagger = Duration(milliseconds: 45);
  static const screenFade = Duration(milliseconds: 300);
}
