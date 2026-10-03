import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Black & white diary / scrapbook palette.
class DiaryColors {
  /// App canvas behind paper/folders
  static const canvas = Color(0xFFE0E0E0);
  static const paper = Color(0xFFFFFFFF);
  static const grid = Color(0xFFC2C2C2);
  static const white = Color(0xFFFFFFFF);
  /// Light greige for "my" feed cards — a wash of the app taupe, still readable.
  static const mineCard = Color(0xFFE0E0E0);
  static const ink = Color(0xFF000000);
  static const inkMuted = Color(0xFF3A3A3A);
  static const inkSoft = Color(0xFF6E6E6E);

  /// Neutral file/folder colors (from reference palette)
  static const fileTaupe = Color(0xFFB4B4B4);
  static const fileStone = Color(0xFFC6C6C6);
  static const fileCream = Color(0xFFCECECE);
  static const fileSand = Color(0xFFBCBCBC);
  static const fileMauve = Color(0xFFCACACA);

  /// Extra neutrals in the same family (avoid clash when many lists)
  static const fileWarmGray = Color(0xFFB8B8B8);
  static const fileMist = Color(0xFFD4D4D4);
  static const fileClay = Color(0xFFC0C0C0);

  static const folderBlue = fileCream;
  static const folderPeach = fileSand;
  static const folderYellow = fileStone;
  static const folderLilac = fileMauve;
  static const folderMint = fileWarmGray;
  static const folderPink = fileClay;

  static const accent = Color(0xFF000000);
  static const pin = Color(0xFF000000);

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
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
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
