// Vicoa Perso — canevas de workflow « façon n8n » pour les agents d'un projet :
// flux de gauche à droite, fond quadrillé à points, nœuds avec icône d'agent et badge d'état,
// poignées d'entrée/sortie, courbes animées quand l'agent travaille, boutons zoom / tout afficher.

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import 'detail_agent_sheet.dart';
import 'perso_commun.dart';
import 'perso_hub.dart';
import 'perso_store.dart';

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
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
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
    final t = FlutterFlowTheme.of(context);
    final g = widget.graphe;
    final d = DispositionGraphe(g);
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final fond = sombre ? const Color(0xFF2B2B2E) : const Color(0xFFF4F4F6);
    final points = sombre ? const Color(0xFF45454B) : const Color(0xFFD3D3DA);

    return LayoutBuilder(builder: (context, contraintes) {
      _taille = Size(contraintes.maxWidth, contraintes.maxHeight);
      if (!_cadre) {
        _cadre = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _toutAfficher(d));
      }
      return Stack(children: [
        Positioned.fill(child: ColoredBox(color: fond)),
        // Grille à points qui suit le zoom et le déplacement.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: controle,
            builder: (_, __) => CustomPaint(painter: _GrillePoints(controle.value, points)),
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
                      repos: t.secondaryText.withValues(alpha: 0.55),
                      vif: t.success,
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
          left: 12,
          bottom: 16,
          child: Material(
            color: t.primaryBackground,
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Tout afficher', icon: const Icon(Icons.fit_screen_rounded), onPressed: () => _toutAfficher(d)),
              IconButton(tooltip: 'Zoom +', icon: const Icon(Icons.zoom_in_rounded), onPressed: () => _zoom(1.25)),
              IconButton(tooltip: 'Zoom −', icon: const Icon(Icons.zoom_out_rounded), onPressed: () => _zoom(0.8)),
            ]),
          ),
        ),
      ]);
    });
  }
}

/// Couleur et icône de l'agent (comme les icônes de nœuds n8n).
({Color couleur, IconData icone, String court}) apparenceAgent(Map s) {
  final type = '${s['agent_type_name'] ?? ''} ${modeleDe(s)}'.toLowerCase();
  if (type.contains('claude')) return (couleur: const Color(0xFFD97757), icone: Icons.auto_awesome_rounded, court: 'Claude');
  if (type.contains('opencode') || type.contains('abliter')) {
    return (couleur: const Color(0xFF3B82F6), icone: Icons.terminal_rounded, court: 'OpenCode');
  }
  if (type.contains('codex') || type.contains('gpt')) return (couleur: const Color(0xFF10A37F), icone: Icons.code_rounded, court: 'Codex');
  if (type.contains('gemini')) return (couleur: const Color(0xFF8E75F0), icone: Icons.diamond_outlined, court: 'Gemini');
  return (couleur: const Color(0xFF7C7C86), icone: Icons.smart_toy_outlined, court: 'Agent');
}

class _NoeudN8n extends StatelessWidget {
  const _NoeudN8n({required this.session, required this.entree, required this.sortie});
  final Map<String, dynamic> session;
  final bool entree, sortie;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final statut = statutDe(session);
    final a = apparenceAgent(session);
    final actif = statut == 'ACTIVE' || statut == 'STARTING';
    final bord = actif ? t.success : statut == 'AWAITING_INPUT' ? t.warning : t.alternate;

    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: Material(
          color: t.primaryBackground,
          elevation: actif ? 4 : 1.5,
          shadowColor: actif ? t.success.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => ouvrirDetailAgent(context, session),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: bord, width: actif ? 2 : 1.4),
              ),
              child: Row(children: [
                // Bloc icône, à gauche (signature visuelle des nœuds n8n).
                Container(
                  width: 54,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: a.couleur.withValues(alpha: 0.14),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
                    border: Border(right: BorderSide(color: t.alternate)),
                  ),
                  child: Icon(a.icone, color: a.couleur, size: 26),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 26, 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nomDe(session),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${a.court} · ${modeleDe(session)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelSmall.copyWith(color: t.secondaryText)),
                        Text(libelleStatut(statut),
                            maxLines: 1, style: t.labelSmall.copyWith(color: couleurStatut(context, statut))),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      // Badge d'état en haut à droite.
      Positioned(right: 6, top: 6, child: _Badge(statut: statut)),
      // Poignées d'entrée / de sortie.
      if (entree) Positioned(left: -6, top: DispositionGraphe.hauteurNoeud / 2 - 6, child: _Poignee(couleur: bord)),
      if (sortie) Positioned(right: -6, top: DispositionGraphe.hauteurNoeud / 2 - 6, child: _Poignee(couleur: bord)),
    ]);
  }
}

class _Poignee extends StatelessWidget {
  const _Poignee({required this.couleur});
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).primaryBackground,
          shape: BoxShape.circle,
          border: Border.all(color: couleur, width: 2),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.statut});
  final String statut;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    switch (statut) {
      case 'ACTIVE':
      case 'STARTING':
        return SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: t.success));
      case 'AWAITING_INPUT':
        return Icon(Icons.pause_circle_filled_rounded, size: 16, color: t.warning);
      case 'COMPLETED':
      case 'REVIEWED':
        return Icon(Icons.check_circle_rounded, size: 16, color: t.success);
      case 'FAILED':
      case 'KILLED':
        return Icon(Icons.error_rounded, size: 16, color: t.error);
      default:
        return Icon(Icons.circle, size: 10, color: t.secondaryText.withValues(alpha: 0.6));
    }
  }
}

/// Courbes de la sortie (droite) d'un nœud vers l'entrée (gauche) du suivant.
/// Quand l'agent destinataire travaille, la courbe passe en vert avec des tirets qui défilent.
class _Connexions extends CustomPainter {
  _Connexions({
    required this.liens,
    required this.dispo,
    required this.phase,
    required this.actif,
    required this.repos,
    required this.vif,
  });
  final List<LienAgent> liens;
  final DispositionGraphe dispo;
  final double phase;
  final bool Function(String id) actif;
  final Color repos, vif;

  @override
  void paint(Canvas canvas, Size size) {
    const w = DispositionGraphe.largeurNoeud, h = DispositionGraphe.hauteurNoeud;
    for (final l in liens) {
      final a = dispo.positions[l.de], b = dispo.positions[l.vers];
      if (a == null || b == null) continue;
      final depart = Offset(a.x + w + 6, a.y + h / 2);
      final arrivee = Offset(b.x - 6, b.y + h / 2);
      final tension = ((arrivee.dx - depart.dx).abs() / 2).clamp(40.0, 160.0);
      final chemin = Path()
        ..moveTo(depart.dx, depart.dy)
        ..cubicTo(depart.dx + tension, depart.dy, arrivee.dx - tension, arrivee.dy, arrivee.dx, arrivee.dy);
      final enCours = actif(l.vers);
      final trait = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = enCours ? 2.4 : 2
        ..color = enCours ? vif : repos;
      if (enCours) {
        // Tirets animés le long de la courbe.
        for (final m in chemin.computeMetrics()) {
          const tiret = 10.0, espace = 7.0;
          var pos = -((tiret + espace) * (1 - phase));
          while (pos < m.length) {
            final debut = pos.clamp(0.0, m.length), fin = (pos + tiret).clamp(0.0, m.length);
            if (fin > debut) canvas.drawPath(m.extractPath(debut, fin), trait);
            pos += tiret + espace;
          }
        }
      } else {
        canvas.drawPath(chemin, trait);
      }
      // Pointe de flèche à l'entrée.
      final pointe = Path()
        ..moveTo(arrivee.dx, arrivee.dy)
        ..lineTo(arrivee.dx - 9, arrivee.dy - 5)
        ..lineTo(arrivee.dx - 9, arrivee.dy + 5)
        ..close();
      canvas.drawPath(pointe, Paint()..color = trait.color);
    }
  }

  @override
  bool shouldRepaint(covariant _Connexions old) => true;
}

/// Fond quadrillé à points, aligné sur le zoom et le déplacement du canevas.
class _GrillePoints extends CustomPainter {
  _GrillePoints(this.matrice, this.couleur);
  final Matrix4 matrice;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final echelle = matrice.getMaxScaleOnAxis();
    final pas = 22.0 * echelle;
    if (pas < 6) return; // trop dézoomé : on évite la bouillie de points
    final tr = matrice.getTranslation();
    final p = Paint()..color = couleur;
    final rayon = (1.3 * echelle).clamp(0.8, 2.0);
    for (var x = tr.x % pas; x < size.width; x += pas) {
      for (var y = tr.y % pas; y < size.height; y += pas) {
        canvas.drawCircle(Offset(x, y), rayon, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GrillePoints old) => old.matrice != matrice || old.couleur != couleur;
}
