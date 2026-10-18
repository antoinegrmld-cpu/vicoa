// Vicoa Perso — page d'un projet : graphe des agents (zoomable) ou vue liste, en temps réel.

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import 'detail_agent_sheet.dart';
import 'perso_commun.dart';
import 'perso_hub.dart';
import 'perso_store.dart';

class ProjetPersoWidget extends StatefulWidget {
  const ProjetPersoWidget({super.key, required this.cle});

  final String cle;

  static String routeName = 'ProjetPerso';
  static String routePath = '/perso/projet/:cle';

  @override
  State<ProjetPersoWidget> createState() => _ProjetPersoWidgetState();
}

class _ProjetPersoWidgetState extends State<ProjetPersoWidget> {
  final store = PersoStore.instance;
  GrapheProjet? graphe;
  bool vueListe = false;
  int _nbSessions = -1;

  @override
  void initState() {
    super.initState();
    store.addListener(_maj);
    store.ouvrir();
    _reconstruire();
  }

  @override
  void dispose() {
    store.removeListener(_maj);
    store.fermer();
    super.dispose();
  }

  ProjetPerso? get projet => store.projetParCle(widget.cle);

  Future<void> _reconstruire() async {
    final p = projet;
    if (p == null) return;
    _nbSessions = p.sessions.length;
    final g = await construireGraphe(p);
    if (mounted) setState(() => graphe = g);
  }

  void _maj() {
    if (!mounted) return;
    // Une session apparaît ou disparaît : on refait le graphe ; sinon, simple rafraîchissement
    // (les nœuds relisent leur état dans le magasin).
    if ((projet?.sessions.length ?? 0) != _nbSessions) _reconstruire();
    setState(() {});
  }

  Map<String, dynamic> _session(String id) =>
      store.sessions.firstWhere((s) => s['id'].toString() == id, orElse: () => {'id': id});

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final p = projet;
    return Scaffold(
      backgroundColor: t.secondaryBackground,
      appBar: AppBar(
        backgroundColor: t.secondaryBackground,
        title: Text(p?.nom ?? 'Projet', style: t.titleMedium),
        actions: [
          IconButton(
            tooltip: vueListe ? 'Vue graphe' : 'Vue liste',
            icon: Icon(vueListe ? Icons.account_tree_rounded : Icons.view_list_rounded),
            onPressed: () => setState(() => vueListe = !vueListe),
          ),
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              await store.charger();
              await _reconstruire();
            },
          ),
        ],
      ),
      body: p == null
          ? Center(child: Text('Projet introuvable.', style: t.bodyMedium))
          : graphe == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${p.sessions.length} session(s) · ${p.agentsActifs} active(s) · liens : ${graphe!.source}',
                          style: t.labelSmall.copyWith(color: t.secondaryText),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(child: vueListe ? _liste(context) : _graphe(context)),
                ]),
    );
  }

  Widget _liste(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final g = graphe!;
    final parents = {for (final l in g.liens) l.vers: l.de};
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
      itemCount: g.sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = _session(g.sessions[i]['id'].toString());
        final statut = statutDe(s);
        final parent = parents[s['id'].toString()];
        return Material(
          color: t.primaryBackground,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.alternate)),
            leading: Pastille(statut: statut, taille: 12),
            title: Text(nomDe(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
            subtitle: Text(
              [
                modeleDe(s),
                libelleStatut(statut),
                if (parent != null) '↖ ${nomDe(_session(parent))}',
              ].where((x) => x.isNotEmpty).join(' · '),
              maxLines: 2,
              style: t.labelSmall.copyWith(color: t.secondaryText),
            ),
            onTap: () => ouvrirDetailAgent(context, s),
          ),
        );
      },
    );
  }

  Widget _graphe(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final g = graphe!;
    if (g.sessions.isEmpty) {
      return Center(child: Text('Aucune session dans ce projet.', style: t.bodyMedium));
    }
    final dispo = DispositionGraphe(g);
    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 2.5,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: dispo.largeur,
        height: dispo.hauteur,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _Fleches(g.liens, dispo, t.secondaryText.withValues(alpha: 0.6)),
            ),
          ),
          for (final s in g.sessions)
            if (dispo.positions[s['id'].toString()] case final pos?)
              Positioned(
                left: pos.x,
                top: pos.y,
                width: DispositionGraphe.largeurNoeud,
                height: DispositionGraphe.hauteurNoeud,
                child: _Noeud(session: _session(s['id'].toString())),
              ),
        ]),
      ),
    );
  }
}

class _Noeud extends StatelessWidget {
  const _Noeud({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final statut = statutDe(session);
    final c = couleurStatut(context, statut);
    return Material(
      color: t.primaryBackground,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ouvrirDetailAgent(context, session),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.7), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(nomDe(session),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
              Text(modeleDe(session),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.labelSmall.copyWith(color: t.secondaryText)),
              Row(children: [
                Pastille(statut: statut, taille: 8),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(libelleStatut(statut),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: t.labelSmall.copyWith(color: c)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flèches orchestrateur -> sous-agents (du bas du parent vers le haut de l'enfant).
class _Fleches extends CustomPainter {
  _Fleches(this.liens, this.dispo, this.couleur);
  final List<LienAgent> liens;
  final DispositionGraphe dispo;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = couleur
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final pointe = Paint()..color = couleur;
    const w = DispositionGraphe.largeurNoeud, h = DispositionGraphe.hauteurNoeud;
    for (final l in liens) {
      final a = dispo.positions[l.de], b = dispo.positions[l.vers];
      if (a == null || b == null) continue;
      final depart = Offset(a.x + w / 2, a.y + h);
      final arrivee = Offset(b.x + w / 2, b.y);
      final milieu = (depart.dy + arrivee.dy) / 2;
      final chemin = Path()
        ..moveTo(depart.dx, depart.dy)
        ..cubicTo(depart.dx, milieu, arrivee.dx, milieu, arrivee.dx, arrivee.dy - 6);
      canvas.drawPath(chemin, trait);
      final tete = Path()
        ..moveTo(arrivee.dx, arrivee.dy)
        ..lineTo(arrivee.dx - 5, arrivee.dy - 9)
        ..lineTo(arrivee.dx + 5, arrivee.dy - 9)
        ..close();
      canvas.drawPath(tete, pointe);
    }
  }

  @override
  bool shouldRepaint(covariant _Fleches old) => true;
}
