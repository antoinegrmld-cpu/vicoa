// Vicoa Perso — accueil (style sombre façon n8n) : grille de cartes « Projets »
// + liste « Conversations hors projet ».

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'canevas_n8n.dart' show apparenceAgent;
import 'detail_agent_sheet.dart';
import 'import_perso_widget.dart';
import 'perso_commun.dart';
import 'perso_store.dart';
import 'perso_theme.dart';
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
    final groupes = store.regrouper();
    final largeur = MediaQuery.sizeOf(context).width;
    final colonnes = largeur > 700 ? 3 : 2;

    return Theme(
      data: themeN8n(context),
      child: Scaffold(
        body: FondPoints(
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: PaletteN8n.accent,
              backgroundColor: PaletteN8n.carte,
              onRefresh: store.charger,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
                      child: Row(children: [
                        const Expanded(
                            child: Text('Mes projets', style: TexteN8n.titre)),
                        if (store.chargement)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        _BoutonImporter(
                            onTap: () =>
                                context.pushNamed(ImportPersoWidget.routeName)),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                      child: Text(
                        '${groupes.projets.length} projet(s) · '
                        '${store.sessions.where((s) => kStatutsActifs.contains(statutDe(s))).length} agent(s) actif(s)',
                        style: TexteN8n.doux,
                      ),
                    ),
                  ),
                  if (store.erreur != null && store.sessions.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                            'Impossible de charger les données : ${store.erreur}',
                            style: TexteN8n.corps
                                .copyWith(color: PaletteN8n.rouge)),
                      ),
                    ),
                  SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colonnes,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.02,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) =>
                            _CarteProjet(projet: groupes.projets[i]),
                        childCount: groupes.projets.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
                      child: Text(
                          'CONVERSATIONS HORS PROJET  ·  ${groupes.horsProjet.length}',
                          style: TexteN8n.etiquette),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    sliver: SliverList.separated(
                      itemCount: groupes.horsProjet.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _LigneConversation(session: groupes.horsProjet[i]),
                    ),
                  ),
                  // Place pour la barre d'onglets flottante.
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoutonImporter extends StatelessWidget {
  const _BoutonImporter({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PaletteN8n.accent.withValues(alpha: 0.14),
        shape: StadiumBorder(
            side: BorderSide(color: PaletteN8n.accent.withValues(alpha: 0.6))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.download_rounded, size: 18, color: PaletteN8n.accent),
              SizedBox(width: 6),
              Text('Importer',
                  style: TextStyle(
                      color: PaletteN8n.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _CarteProjet extends StatelessWidget {
  const _CarteProjet({required this.projet});
  final ProjetPerso projet;

  @override
  Widget build(BuildContext context) {
    final statut = statutProjet(projet);
    final actifs = projet.agentsActifs;
    final enTravail = statut == 'ACTIVE';
    final enAttente = statut == 'AWAITING_INPUT';
    final couleurEtat = couleurStatutN8n(statut);
    // Icônes des agents qui tournent (au plus 4), comme une rangée de nœuds miniatures.
    final agents = projet.sessions
        .where((s) => kStatutsActifs.contains(statutDe(s)))
        .take(4)
        .toList();

    return CarteN8n(
      accent: enTravail || enAttente ? couleurEtat : null,
      halo: enTravail,
      padding: const EdgeInsets.all(14),
      onTap: () => context.pushNamed(ProjetPersoWidget.routeName,
          pathParameters: {'cle': projet.cle}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const BlocIcone(
                icone: Icons.account_tree_rounded,
                couleur: PaletteN8n.accent,
                taille: 40),
            const Spacer(),
            _PastilleN8n(statut: statut),
          ]),
          const SizedBox(height: 12),
          Text(projet.nom,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TexteN8n.fort),
          const Spacer(),
          if (agents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                for (final s in agents)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: BlocIcone(
                        icone: apparenceAgent(s).icone,
                        couleur: apparenceAgent(s).couleur,
                        taille: 22),
                  ),
              ]),
            ),
          Text(
            actifs == 0
                ? 'Aucun agent actif'
                : '$actifs agent${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''}',
            style: TexteN8n.doux.copyWith(
                color: actifs > 0 ? couleurEtat : PaletteN8n.texteDoux,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
              '${projet.sessions.length} session${projet.sessions.length > 1 ? 's' : ''} · ${ilYA(projet.derniereActivite)}',
              style: TexteN8n.doux),
        ],
      ),
    );
  }
}

class _PastilleN8n extends StatelessWidget {
  const _PastilleN8n({required this.statut});
  final String statut;

  @override
  Widget build(BuildContext context) {
    final c = couleurStatutN8n(statut);
    final vivant = statut == 'ACTIVE' || statut == 'STARTING';
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: vivant || statut == 'AWAITING_INPUT' ? c : PaletteN8n.lien,
        shape: BoxShape.circle,
        boxShadow: vivant
            ? [
                BoxShadow(
                    color: c.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 1)
              ]
            : null,
      ),
    );
  }
}

class _LigneConversation extends StatelessWidget {
  const _LigneConversation({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final statut = statutDe(session);
    final a = apparenceAgent(session);
    return CarteN8n(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      accent:
          statut == 'ACTIVE' || statut == 'STARTING' ? PaletteN8n.vert : null,
      onTap: () => ouvrirDetailAgent(context, session),
      child: Row(children: [
        BlocIcone(icone: a.icone, couleur: a.couleur, taille: 38),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nomDe(session),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TexteN8n.fort),
            const SizedBox(height: 3),
            Text('${libelleStatut(statut)} · ${ilYA(dateDe(session))}',
                style: TexteN8n.doux.copyWith(color: couleurStatutN8n(statut))),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: PaletteN8n.texteDoux),
      ]),
    );
  }
}
