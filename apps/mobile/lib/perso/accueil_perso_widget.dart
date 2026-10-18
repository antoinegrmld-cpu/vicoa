// Vicoa Perso — accueil : grille de cartes « Projets » + liste « Conversations hors projet ».

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import 'detail_agent_sheet.dart';
import 'import_perso_widget.dart';
import 'perso_commun.dart';
import 'perso_store.dart';
import 'projet_perso_widget.dart';

class AccueilPersoWidget extends StatefulWidget {
  const AccueilPersoWidget({super.key});

  @override
  State<AccueilPersoWidget> createState() => _AccueilPersoWidgetState();
}

class _AccueilPersoWidgetState extends State<AccueilPersoWidget> {
  final store = PersoStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_maj);
    store.ouvrir();
  }

  @override
  void dispose() {
    store.removeListener(_maj);
    store.fermer();
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final groupes = store.regrouper();
    final largeur = MediaQuery.sizeOf(context).width;
    final colonnes = largeur > 700 ? 3 : 2;

    return Scaffold(
      backgroundColor: t.secondaryBackground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: store.charger,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('Mes projets', style: t.headlineSmall)),
                      if (store.chargement)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      TextButton.icon(
                        onPressed: () => context.pushNamed(ImportPersoWidget.routeName),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: const Text('Importer'),
                      ),
                    ],
                  ),
                ),
              ),
              if (store.erreur != null && store.sessions.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Impossible de charger les données : ${store.erreur}',
                        style: t.bodyMedium.copyWith(color: t.error)),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: colonnes,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.15,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _CarteProjet(projet: groupes.projets[i]),
                    childCount: groupes.projets.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text('Conversations hors projet (${groupes.horsProjet.length})',
                      style: t.titleMedium),
                ),
              ),
              SliverList.builder(
                itemCount: groupes.horsProjet.length,
                itemBuilder: (context, i) => _LigneConversation(session: groupes.horsProjet[i]),
              ),
              // Place pour la barre d'onglets flottante.
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteProjet extends StatelessWidget {
  const _CarteProjet({required this.projet});
  final ProjetPerso projet;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final statut = statutProjet(projet);
    final actifs = projet.agentsActifs;
    return Material(
      color: t.primaryBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(
          ProjetPersoWidget.routeName,
          pathParameters: {'cle': projet.cle},
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.alternate),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.folder_rounded, color: t.primary, size: 22),
                const Spacer(),
                Pastille(statut: statut, taille: 12),
              ]),
              const SizedBox(height: 10),
              Text(projet.nom,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const Spacer(),
              Text(
                actifs == 0
                    ? 'Aucun agent actif'
                    : '$actifs agent${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''}',
                style: t.bodySmall.copyWith(
                    color: actifs > 0 ? couleurStatut(context, statut) : t.secondaryText),
              ),
              const SizedBox(height: 2),
              Text('${projet.sessions.length} session${projet.sessions.length > 1 ? 's' : ''} · '
                  '${ilYA(projet.derniereActivite)}',
                  style: t.labelSmall.copyWith(color: t.secondaryText)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneConversation extends StatelessWidget {
  const _LigneConversation({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final statut = statutDe(session);
    return ListTile(
      leading: Pastille(statut: statut),
      minLeadingWidth: 12,
      title: Text(nomDe(session), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
      subtitle: Text('${libelleStatut(statut)} · ${ilYA(dateDe(session))}',
          style: t.labelSmall.copyWith(color: t.secondaryText)),
      trailing: Icon(Icons.chevron_right, color: t.secondaryText),
      onTap: () => ouvrirDetailAgent(context, session),
    );
  }
}
