// Vicoa Perso — style sombre « façon n8n » partagé par tous les écrans Perso :
// palette, thème Material sombre, cartes (dégradé + ombre douce), fond à points, bloc d'icône.

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// Palette sombre fixe (indépendante du thème clair/sombre du téléphone).
class PaletteN8n {
  static const fond = Color(0xFF1C1C21);
  static const points = Color(0xFF34343C);
  static const carte = Color(0xFF26262D);
  static const carteHaut = Color(0xFF2C2C34);
  static const champ = Color(0xFF202026);
  static const bord = Color(0xFF3D3D47);
  static const texte = Color(0xFFEDEDF2);
  static const texteDoux = Color(0xFF9B9BA8);
  static const lien = Color(0xFF5C5C68);
  static const vert = Color(0xFF3DDC97);
  static const orange = Color(0xFFF5A524);
  static const rouge = Color(0xFFF25F5C);
  static const accent =
      Color(0xFFFF6D5A); // corail des boutons principaux de n8n
  static const commandes = Color(0xFF2A2A31);
}

Color couleurStatutN8n(String statut) {
  switch (statut) {
    case 'ACTIVE':
    case 'STARTING':
      return PaletteN8n.vert;
    case 'AWAITING_INPUT':
      return PaletteN8n.orange;
    case 'FAILED':
    case 'KILLED':
      return PaletteN8n.rouge;
    default:
      return PaletteN8n.texteDoux;
  }
}

/// Styles de texte (police de l'appli, couleurs de la palette).
class TexteN8n {
  static const titre = TextStyle(
      color: PaletteN8n.texte,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2);
  static const sousTitre = TextStyle(
      color: PaletteN8n.texte,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25);
  static const corps =
      TextStyle(color: PaletteN8n.texte, fontSize: 14.5, height: 1.35);
  static const fort = TextStyle(
      color: PaletteN8n.texte,
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
      height: 1.25);
  static const doux =
      TextStyle(color: PaletteN8n.texteDoux, fontSize: 12, height: 1.3);
  static const etiquette = TextStyle(
      color: PaletteN8n.texteDoux,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6);
}

/// Thème Material sombre : boutons, cases à cocher, champs, puces et messages prennent le style n8n.
ThemeData themeN8n(BuildContext context) {
  final base = Theme.of(context);
  const schema = ColorScheme.dark(
    primary: PaletteN8n.accent,
    onPrimary: Colors.white,
    secondary: PaletteN8n.vert,
    surface: PaletteN8n.carte,
    onSurface: PaletteN8n.texte,
    error: PaletteN8n.rouge,
    outline: PaletteN8n.bord,
  );
  return base.copyWith(
    brightness: Brightness.dark,
    colorScheme: schema,
    scaffoldBackgroundColor: PaletteN8n.fond,
    canvasColor: PaletteN8n.fond,
    dividerColor: PaletteN8n.bord,
    appBarTheme: const AppBarTheme(
      backgroundColor: PaletteN8n.fond,
      foregroundColor: PaletteN8n.texte,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TexteN8n.sousTitre,
    ),
    iconTheme: const IconThemeData(color: PaletteN8n.texte),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: PaletteN8n.accent),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? PaletteN8n.accent
              : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: PaletteN8n.lien, width: 1.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: PaletteN8n.carte,
      selectedColor: PaletteN8n.accent.withValues(alpha: 0.22),
      side: const BorderSide(color: PaletteN8n.bord),
      labelStyle: const TextStyle(color: PaletteN8n.texte, fontSize: 13),
      checkmarkColor: PaletteN8n.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PaletteN8n.champ,
      labelStyle: const TextStyle(color: PaletteN8n.texteDoux),
      hintStyle: const TextStyle(color: PaletteN8n.texteDoux),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: PaletteN8n.bord)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: PaletteN8n.bord)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: PaletteN8n.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PaletteN8n.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PaletteN8n.carteHaut,
        disabledForegroundColor: PaletteN8n.texteDoux,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: PaletteN8n.texte),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PaletteN8n.carteHaut,
      contentTextStyle: TextStyle(color: PaletteN8n.texte),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme:
        const TextSelectionThemeData(cursorColor: PaletteN8n.accent),
  );
}

/// Carte sombre : léger dégradé, bord fin, ombre douce ; bord coloré et halo si [accent].
class CarteN8n extends StatelessWidget {
  const CarteN8n(
      {super.key,
      required this.child,
      this.accent,
      this.halo = false,
      this.onTap,
      this.padding,
      this.rayon = 12});

  final Widget child;
  final Color? accent;
  final bool halo;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double rayon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rayon),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PaletteN8n.carteHaut, PaletteN8n.carte],
        ),
        border: Border.all(
            color: accent ?? PaletteN8n.bord,
            width: accent != null ? 1.6 : 1.1),
        boxShadow: [
          const BoxShadow(
              color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
          if (halo && accent != null)
            BoxShadow(
                color: accent!.withValues(alpha: 0.26),
                blurRadius: 18,
                spreadRadius: 1),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(rayon),
          splashColor: Colors.white10,
          highlightColor: Colors.white10,
          onTap: onTap,
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

/// Bloc d'icône coloré (comme sur les nœuds n8n).
class BlocIcone extends StatelessWidget {
  const BlocIcone(
      {super.key,
      required this.icone,
      required this.couleur,
      this.taille = 44});
  final IconData icone;
  final Color couleur;
  final double taille;

  @override
  Widget build(BuildContext context) => Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(taille * 0.22),
          border: Border.all(color: couleur.withValues(alpha: 0.35)),
        ),
        child: Icon(icone, color: couleur, size: taille * 0.54),
      );
}

/// Fond sombre à points discrets (fixe), pour les écrans hors canevas.
class FondPoints extends StatelessWidget {
  const FondPoints({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: PaletteN8n.fond)),
        Positioned.fill(
            child: RepaintBoundary(
                child: CustomPaint(painter: GrillePoints(Matrix4.identity())))),
        child,
      ]);
}

/// Grille de points alignée sur une transformation (zoom / déplacement).
class GrillePoints extends CustomPainter {
  GrillePoints(this.matrice);
  final Matrix4 matrice;

  @override
  void paint(Canvas canvas, Size size) {
    final echelle = matrice.getMaxScaleOnAxis();
    var pas = 24.0 * echelle;
    while (pas < 12) {
      pas *=
          2; // dézoom important : on espace les points au lieu de les entasser
    }
    final tr = matrice.getTranslation();
    final points = <Offset>[];
    for (var x = tr.x % pas; x < size.width; x += pas) {
      for (var y = tr.y % pas; y < size.height; y += pas) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..isAntiAlias = true
        ..color = PaletteN8n.points
        ..strokeWidth = (2.4 * echelle).clamp(1.6, 3.2)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant GrillePoints old) => old.matrice != matrice;
}
