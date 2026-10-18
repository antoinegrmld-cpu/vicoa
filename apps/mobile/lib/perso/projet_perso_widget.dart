// Vicoa Perso — page d'un projet : graphe des agents (zoomable) ou vue liste, en temps réel.

import 'dart:async';

import 'package:flutter/material.dart';

import 'canevas_n8n.dart';
import 'detail_agent_sheet.dart';
import 'perso_commun.dart' show libelleStatut;
import 'perso_hub.dart';
import 'perso_store.dart';
import 'perso_theme.dart';

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
  Timer? _lanes;

  @override
  void initState() {
    super.initState();
    store.addListener(_maj);
    store.ouvrir();
    _reconstruire();
    // Les lanes lancées par l'orchestrateur sont détectées sur le PC : on relit toutes les 20 s.
    _lanes =
        Timer.periodic(const Duration(seconds: 20), (_) => _reconstruire());
  }

  @override
  void dispose() {
    store.removeListener(_maj);
    store.fermer();
    _lanes?.cancel();
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

  /// Session à jour : depuis Vicoa (temps réel), sinon le nœud « lane du PC » du graphe.
  Map<String, dynamic> _session(String id) => store.sessions.firstWhere(
        (s) => s['id'].toString() == id,
        orElse: () =>
            graphe?.sessions.firstWhere((s) => s['id'].toString() == id,
                orElse: () => {'id': id}) ??
            {'id': id},
      );

  @override
  Widget build(BuildContext context) {
    final p = projet;
    // Toute la page en sombre, comme n8n (vue graphe et vue liste).
    return Theme(
      data: themeN8n(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(p?.nom ?? 'Projet',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: vueListe ? 'Vue graphe' : 'Vue liste',
              icon: Icon(vueListe
                  ? Icons.account_tree_rounded
                  : Icons.view_list_rounded),
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
            ? const Center(
                child: Text('Projet introuvable.', style: TexteN8n.corps))
            : graphe == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            '${p.sessions.length} session(s) · ${p.agentsActifs} active(s) · liens : ${graphe!.source}',
                            style: TexteN8n.doux,
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                        child: vueListe ? _liste(context) : _graphe(context)),
                  ]),
      ),
    );
  }

  Widget _liste(BuildContext context) {
    final g = graphe!;
    final parents = {for (final l in g.liens) l.vers: l.de};
    return FondPoints(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
        itemCount: g.sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final s = _session(g.sessions[i]['id'].toString());
          final statut = statutDe(s);
          final parent = parents[s['id'].toString()];
          final a = apparenceAgent(s);
          final actif = statut == 'ACTIVE' || statut == 'STARTING';
          return CarteN8n(
            accent: actif || statut == 'AWAITING_INPUT'
                ? couleurStatutN8n(statut)
                : null,
            halo: actif,
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            onTap: () => ouvrirDetailAgent(context, s),
            child: Row(children: [
              BlocIcone(icone: a.icone, couleur: a.couleur, taille: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nomDe(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TexteN8n.fort),
                      const SizedBox(height: 3),
                      Text('${a.court} · ${modeleDe(s)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TexteN8n.doux),
                      const SizedBox(height: 2),
                      Text(
                        [
                          libelleStatut(statut),
                          if (parent != null)
                            'piloté par ${nomDe(_session(parent))}'
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TexteN8n.doux
                            .copyWith(color: couleurStatutN8n(statut)),
                      ),
                    ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _graphe(BuildContext context) {
    final g = graphe!;
    if (g.sessions.isEmpty) {
      return const Center(
          child: Text('Aucune session dans ce projet.', style: TexteN8n.corps));
    }
    // Canevas façon n8n (voir canevas_n8n.dart). La clé force un nouveau cadrage si le graphe change.
    return CanevasAgents(
      key: ValueKey('${g.source}-${g.sessions.length}-${g.liens.length}'),
      graphe: g,
      session: _session,
    );
  }
}
