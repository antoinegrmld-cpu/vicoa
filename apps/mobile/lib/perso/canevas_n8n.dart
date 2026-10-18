// Vicoa Perso — canevas de workflow « façon n8n » pour les agents d'un projet.
// Toujours sombre (comme n8n) : fond presque noir à points, cartes anthracite avec ombre douce,
// flux de gauche à droite, poignées, courbes lissées animées quand l'agent travaille,
// commandes zoom + / zoom − / tout afficher.

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'detail_agent_sheet.dart';
import 'perso_commun.dart' show libelleStatut;
import 'perso_hub.dart';
import 'perso_store.dart';

/// Palette sombre fixe (indépendante du thème clair/sombre du téléphone).
class PaletteN8n {
  static const fond = Color(0xFF1C1C21);
  static const points = Color(0xFF34343C);
  static const carte = Color(0xFF26262D);
  static const carteHaut = Color(0xFF2C2C34);
  static const bord = Color(0xFF3D3D47);
  static const texte = Color(0xFFEDEDF2);
  static const texteDoux = Color(0xFF9B9BA8);
  static const lien = Color(0xFF5C5C68);
  static const vert = Color(0xFF3DDC97);
  static const orange = Color(0xFFF5A524);
  static const rouge = Color(0xFFF25F5C);
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

class CanevasAgents extends StatefulWidget {
  const CanevasAgents({super.key, required this.graphe, required this.session});

  final GrapheProjet graphe;

  /// Version à jour d'une session (temps réel) à partir de son id.
  final Map<String, dynamic> Function(String id) session;

  @override
  State<CanevasAgents> createState() => _CanevasAgentsState();
}

class _CanevasAgentsState extends State<CanevasAgents> with SingleTickerProviderStateMixin {
  final controle = TransformationController();
  late final AnimationController flux =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  Size? _taille;
  bool _cadre = false;

  @override
  void dispose() {
    controle.dispose();
    flux.dispose();
    super.dispose();
  }

  void _toutAfficher(DispositionGraphe d) {
    final t = _taille;
    if (t == null) return;
    // Tout faire tenir, sans descendre sous un zoom où les textes restent lisibles sur téléphone.
    const echelleMin = 0.7;
    final ideale = [t.width / d.largeur, t.height / d.hauteur, 1.0].reduce((a, b) => a < b ? a : b);
    final echelle = ideale < echelleMin ? echelleMin : ideale;
    final largeurVue = d.largeur * echelle, hauteurVue = d.hauteur * echelle;
    // Trop large : on cale le début du flux (l'orchestrateur) à gauche ; sinon on centre.
    final dx = largeurVue > t.width ? 0.0 : (t.width - largeurVue) / 2;
    final dy = hauteurVue > t.height ? 0.0 : (t.height - hauteurVue) / 2;
    controle.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(echelle, echelle, 1, 1);
  }

  void _zoom(double facteur) {
    final t = _taille;
    if (t == null) return;
    final c = Offset(t.width / 2, t.height / 2);
    controle.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(facteur, facteur, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(controle.value);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.graphe;
    final d = DispositionGraphe(g);

    return LayoutBuilder(builder: (context, contraintes) {
      _taille = Size(contraintes.maxWidth, contraintes.maxHeight);
      if (!_cadre) {
        _cadre = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _toutAfficher(d));
      }
      return Stack(children: [
        const Positioned.fill(child: ColoredBox(color: PaletteN8n.fond)),
        // Grille à points qui suit le zoom et le déplacement.
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: controle,
              builder: (_, __) => CustomPaint(painter: _GrillePoints(controle.value)),
            ),
          ),
        ),
        InteractiveViewer(
          transformationController: controle,
          constrained: false,
          minScale: 0.25,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: SizedBox(
            width: d.largeur,
            height: d.hauteur,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: flux,
                    builder: (_, __) => CustomPaint(
                      painter: _Connexions(
                        liens: g.liens,
                        dispo: d,
                        phase: flux.value,
                        actif: (id) {
                          final s = statutDe(widget.session(id));
                          return s == 'ACTIVE' || s == 'STARTING';
                        },
                      ),
                    ),
                  ),
                ),
              ),
              for (final s in g.sessions)
                if (d.positions[s['id'].toString()] case final pos?)
                  Positioned(
                    left: pos.x,
                    top: pos.y,
                    width: DispositionGraphe.largeurNoeud,
                    height: DispositionGraphe.hauteurNoeud,
                    child: _NoeudN8n(
                      session: widget.session(s['id'].toString()),
                      entree: g.liens.any((l) => l.vers == s['id'].toString()),
                      sortie: g.liens.any((l) => l.de == s['id'].toString()),
                    ),
                  ),
            ]),
          ),
        ),
        // Commandes en bas à gauche, comme dans n8n.
        Positioned(
          left: 14,
          bottom: 18,
          child: Container(
            decoration: BoxDecoration(
              color: PaletteN8n.commandes,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PaletteN8n.bord),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _BoutonCommande(icone: Icons.fit_screen_rounded, aide: 'Tout afficher', action: () => _toutAfficher(d)),
              _BoutonCommande(icone: Icons.add_rounded, aide: 'Zoom +', action: () => _zoom(1.25)),
              _BoutonCommande(icone: Icons.remove_rounded, aide: 'Zoom −', action: () => _zoom(0.8)),
            ]),
          ),
        ),
      ]);
    });
  }
}

class _BoutonCommande extends StatelessWidget {
  const _BoutonCommande({required this.icone, required this.aide, required this.action});
  final IconData icone;
  final String aide;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: aide,
        onPressed: action,
        icon: Icon(icone, color: PaletteN8n.texte, size: 22),
        splashRadius: 22,
      );
}

/// Couleur et icône de l'agent (comme les icônes de nœuds n8n).
({Color couleur, IconData icone, String court}) apparenceAgent(Map s) {
  final type = '${s['agent_type_name'] ?? ''} ${modeleDe(s)}'.toLowerCase();
  if (type.contains('claude')) return (couleur: const Color(0xFFE58A68), icone: Icons.auto_awesome_rounded, court: 'Claude');
  if (type.contains('opencode') || type.contains('abliter')) {
    return (couleur: const Color(0xFF5B9DFF), icone: Icons.terminal_rounded, court: 'OpenCode');
  }
  if (type.contains('codex') || type.contains('gpt')) return (couleur: const Color(0xFF2CC497), icone: Icons.code_rounded, court: 'Codex');
  if (type.contains('gemini')) return (couleur: const Color(0xFFA48BFF), icone: Icons.diamond_outlined, court: 'Gemini');
  return (couleur: const Color(0xFFA0A0AE), icone: Icons.smart_toy_outlined, court: 'Agent');
}

class _NoeudN8n extends StatelessWidget {
  const _NoeudN8n({required this.session, required this.entree, required this.sortie});
  final Map<String, dynamic> session;
  final bool entree, sortie;

  @override
  Widget build(BuildContext context) {
    final statut = statutDe(session);
    final a = apparenceAgent(session);
    final actif = statut == 'ACTIVE' || statut == 'STARTING';
    final couleurEtat = couleurStatutN8n(statut);
    final bord = actif || statut == 'AWAITING_INPUT' ? couleurEtat : PaletteN8n.bord;
    const rayon = 12.0;

    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(rayon),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PaletteN8n.carteHaut, PaletteN8n.carte],
            ),
            border: Border.all(color: bord, width: actif ? 1.8 : 1.2),
            boxShadow: [
              const BoxShadow(color: Color(0x73000000), blurRadius: 16, offset: Offset(0, 6)),
              if (actif) BoxShadow(color: PaletteN8n.vert.withValues(alpha: 0.28), blurRadius: 18, spreadRadius: 1),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(rayon),
              splashColor: Colors.white10,
              highlightColor: Colors.white10,
              onTap: () => ouvrirDetailAgent(context, session),
              child: Row(children: [
                // Bloc icône (signature visuelle des nœuds n8n).
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: a.couleur.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: a.couleur.withValues(alpha: 0.35)),
                    ),
                    child: Icon(a.icone, color: a.couleur, size: 26),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 28, 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nomDe(session),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: PaletteN8n.texte, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.2)),
                        const SizedBox(height: 3),
                        Text('${a.court} · ${modeleDe(session)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: PaletteN8n.texteDoux, fontSize: 11.5, height: 1.2)),
                        const SizedBox(height: 3),
                        Text(libelleStatut(statut),
                            maxLines: 1,
                            style: TextStyle(color: couleurEtat, fontSize: 11.5, fontWeight: FontWeight.w500, height: 1.2)),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      Positioned(right: 9, top: 9, child: _Badge(statut: statut)),
      if (entree) Positioned(left: -7, top: DispositionGraphe.hauteurNoeud / 2 - 7, child: _Poignee(couleur: bord)),
      if (sortie) Positioned(right: -7, top: DispositionGraphe.hauteurNoeud / 2 - 7, child: _Poignee(couleur: bord)),
    ]);
  }
}

class _Poignee extends StatelessWidget {
  const _Poignee({required this.couleur});
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: PaletteN8n.fond,
          shape: BoxShape.circle,
          border: Border.all(color: couleur == PaletteN8n.bord ? PaletteN8n.lien : couleur, width: 2),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.statut});
  final String statut;

  @override
  Widget build(BuildContext context) {
    switch (statut) {
      case 'ACTIVE':
      case 'STARTING':
        return const SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: PaletteN8n.vert));
      case 'AWAITING_INPUT':
        return const Icon(Icons.pause_circle_filled_rounded, size: 17, color: PaletteN8n.orange);
      case 'COMPLETED':
      case 'REVIEWED':
        return const Icon(Icons.check_circle_rounded, size: 17, color: PaletteN8n.vert);
      case 'FAILED':
      case 'KILLED':
        return const Icon(Icons.error_rounded, size: 17, color: PaletteN8n.rouge);
      default:
        return const Icon(Icons.circle, size: 9, color: PaletteN8n.lien);
    }
  }
}

/// Courbes lissées de la sortie (droite) d'un nœud vers l'entrée (gauche) du suivant.
/// Agent destinataire au travail : courbe verte, halo léger, points lumineux qui défilent.
class _Connexions extends CustomPainter {
  _Connexions({required this.liens, required this.dispo, required this.phase, required this.actif});
  final List<LienAgent> liens;
  final DispositionGraphe dispo;
  final double phase;
  final bool Function(String id) actif;

  @override
  void paint(Canvas canvas, Size size) {
    const w = DispositionGraphe.largeurNoeud, h = DispositionGraphe.hauteurNoeud;
    for (final l in liens) {
      final a = dispo.positions[l.de], b = dispo.positions[l.vers];
      if (a == null || b == null) continue;
      final depart = Offset(a.x + w + 7, a.y + h / 2);
      final arrivee = Offset(b.x - 9, b.y + h / 2);
      final tension = ((arrivee.dx - depart.dx).abs() * 0.5).clamp(40.0, 180.0);
      final chemin = Path()
        ..moveTo(depart.dx, depart.dy)
        ..cubicTo(depart.dx + tension, depart.dy, arrivee.dx - tension, arrivee.dy, arrivee.dx, arrivee.dy);
      final enCours = actif(l.vers);
      final couleur = enCours ? PaletteN8n.vert : PaletteN8n.lien;

      if (enCours) {
        // Halo doux sous la courbe.
        canvas.drawPath(
          chemin,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..color = PaletteN8n.vert.withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawPath(
        chemin,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = enCours ? 2.4 : 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = couleur,
      );
      if (enCours) {
        // Points lumineux qui avancent le long de la courbe (sens du flux).
        final point = Paint()
          ..isAntiAlias = true
          ..color = const Color(0xFFCFFFE8);
        for (final m in chemin.computeMetrics()) {
          const espacement = 46.0;
          for (var pos = (phase * espacement) % espacement; pos < m.length; pos += espacement) {
            final t = m.getTangentForOffset(pos);
            if (t != null) canvas.drawCircle(t.position, 2.2, point);
          }
        }
      }
      // Pointe de flèche aux angles arrondis.
      final pointe = Path()
        ..moveTo(arrivee.dx + 2, arrivee.dy)
        ..lineTo(arrivee.dx - 8, arrivee.dy - 5.5)
        ..quadraticBezierTo(arrivee.dx - 6.5, arrivee.dy, arrivee.dx - 8, arrivee.dy + 5.5)
        ..close();
      canvas.drawPath(
          pointe,
          Paint()
            ..isAntiAlias = true
            ..color = couleur
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _Connexions old) => true;
}

/// Fond à points discrets, aligné sur le zoom et le déplacement du canevas.
class _GrillePoints extends CustomPainter {
  _GrillePoints(this.matrice);
  final Matrix4 matrice;

  @override
  void paint(Canvas canvas, Size size) {
    final echelle = matrice.getMaxScaleOnAxis();
    var pas = 24.0 * echelle;
    while (pas < 12) {
      pas *= 2; // dézoom important : on espace les points au lieu de les entasser
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
  bool shouldRepaint(covariant _GrillePoints old) => old.matrice != matrice;
}
