import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Gender-neutral MZ diary / scrapbook palette.
class DiaryColors {
  /// App canvas behind paper/folders
  static const canvas = Color(0xFFECECEA);
  static const paper = Color(0xFFF7F4EE);
  static const grid = Color(0xFFD9D2C6);
  static const white = Color(0xFFFFFFFF);
  /// Light greige for "my" feed cards — a wash of the app taupe, still readable.
  static const mineCard = Color(0xFFEFEBE4);
  static const ink = Color(0xFF2F2A26);
  static const inkMuted = Color(0xFF8B7E74);
  static const inkSoft = Color(0xFFB0A69C);

  /// Neutral file/folder colors (from reference palette)
  static const fileTaupe = Color(0xFFB1A18A);
  static const fileStone = Color(0xFFC5BEAC);
  static const fileCream = Color(0xFFE6D9C8);
  static const fileSand = Color(0xFFD5BAA5);
  static const fileMauve = Color(0xFFC1AAA2);

  /// Extra neutrals in the same family (avoid clash when many lists)
  static const fileWarmGray = Color(0xFFCBB9A8);
  static const fileMist = Color(0xFFD8CFC3);
  static const fileClay = Color(0xFFC8B39E);

  static const folderBlue = fileCream;
  static const folderPeach = fileSand;
  static const folderYellow = fileStone;
  static const folderLilac = fileMauve;
  static const folderMint = fileWarmGray;
  static const folderPink = fileClay;

  static const accent = Color(0xFF6B7F6A);
  static const pin = Color(0xFFB86B5A);

  /// Pool used when creating new lists (prefer unused first).
  static const fileColors = [
    fileTaupe,
    fileStone,
    fileCream,
    fileSand,
    fileMauve,
    fileWarmGray,
    fileMist,
    fileClay,
  ];

  /// Alias kept for older call sites.
  static const pastels = fileColors;
}

class DiaryTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DiaryColors.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DiaryColors.accent,
        brightness: Brightness.light,
        surface: DiaryColors.paper,
      ),
    );

    // UI default: rounded readable gothic (Jeonggam-like via Jua)
    final uiText = GoogleFonts.juaTextTheme(base.textTheme).apply(
      bodyColor: DiaryColors.ink,
      displayColor: DiaryColors.ink,
    );

    return base.copyWith(
      textTheme: uiText,
      primaryTextTheme: uiText,
      appBarTheme: AppBarTheme(
        backgroundColor: DiaryColors.white,
        foregroundColor: DiaryColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: ui(20, weight: FontWeight.w500),
      ),
    );
  }

  /// Rounded UI font for labels, tabs, buttons, banners (not product data).
  /// [size] is a design-pixel value at 390pt width; [DiaryScale] scales the tree.
  static TextStyle ui(
    double size, {
    Color? color,
    FontWeight? weight,
  }) {
    return GoogleFonts.jua(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? DiaryColors.ink,
      height: 1.25,
    );
  }

  /// Display / title (still soft, not overly feminine).
  static TextStyle display(double size, {Color? color, FontWeight? weight}) {
    return GoogleFonts.jua(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w500,
      color: color ?? DiaryColors.ink,
      height: 1.1,
    );
  }

  /// Parsed product info (store, name, price) — keep clean gothic.
  static TextStyle product(
    double size, {
    Color? color,
    FontWeight? weight,
  }) {
    return GoogleFonts.notoSansKr(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? DiaryColors.ink,
      height: 1.35,
    );
  }

  /// Backward-compatible alias → UI font.
  static TextStyle body(
    double size, {
    Color? color,
    FontWeight? weight,
  }) =>
      ui(size, color: color, weight: weight);
}
