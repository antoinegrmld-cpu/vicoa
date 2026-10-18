// Vicoa Perso — page d'un projet : graphe des agents (zoomable) ou vue liste, en temps réel.

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import 'canevas_n8n.dart';
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
      // Vue graphe : tout l'écran en sombre, comme n8n.
      backgroundColor: vueListe ? t.secondaryBackground : PaletteN8n.fond,
      appBar: AppBar(
        backgroundColor: vueListe ? t.secondaryBackground : PaletteN8n.fond,
        foregroundColor: vueListe ? t.primaryText : PaletteN8n.texte,
        surfaceTintColor: Colors.transparent,
        title: Text(p?.nom ?? 'Projet',
            style: t.titleMedium.copyWith(color: vueListe ? t.primaryText : PaletteN8n.texte)),
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
                          style: t.labelSmall.copyWith(color: vueListe ? t.secondaryText : PaletteN8n.texteDoux),
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
    // Canevas façon n8n (voir canevas_n8n.dart). La clé force un nouveau cadrage si le graphe change.
    return CanevasAgents(
      key: ValueKey('${g.source}-${g.sessions.length}-${g.liens.length}'),
      graphe: g,
      session: _session,
    );
  }
}
