import 'package:flutter/material.dart';

/// Pfade zu freigegebenen Markenassets (siehe `assets/brand/`).
///
/// - [wordmark]: Textmarke „RettBase Campus“ – **PNG mit Alphakanal** (RGBA),
///   damit der AppBar-/Seitenhintergrund durchscheint (kein weißes „Plakat“).
/// - [appIcon]: RB-Quadrat für Launcher / Web-Favicon / kompaktes Icon.
abstract final class CampusBrandAssets {
  static const String wordmarkPng = 'assets/brand/campus_logo_wordmark.png';
  static const String appIconPng = 'assets/brand/campus_app_icon.png';

  static Widget wordmark({double height = 36, AlignmentGeometry alignment = Alignment.center}) {
    return Align(
      alignment: alignment,
      child: Image.asset(
        wordmarkPng,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'RettBase Campus',
      ),
    );
  }

  static Widget iconMark({double size = 28}) {
    return Image.asset(
      appIconPng,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'RettBase Campus',
    );
  }
}
