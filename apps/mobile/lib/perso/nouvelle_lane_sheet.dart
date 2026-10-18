// Vicoa Perso — bouton « + » d'un projet : Antoine lance lui-même une lane (OpenCode ou Claude Code) sur le PC,
// reliée à l'orchestrateur (ou à un autre nœud du graphe). Le PC utilise le même code que l'outil vicoa_lancer_lane.

import 'package:flutter/material.dart';

import 'perso_hub.dart';
import 'perso_pc.dart';
import 'perso_store.dart';
import 'perso_theme.dart';

/// Ouvre le formulaire ; renvoie le session_id de la lane lancée, ou null.
Future<String?> ouvrirNouvelleLane(
    BuildContext context, ProjetPerso projet, GrapheProjet? graphe) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PaletteN8n.carte,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => Theme(
      data: themeN8n(context),
      child: _NouvelleLane(projet: projet, graphe: graphe),
    ),
  );
}

class _NouvelleLane extends StatefulWidget {
  const _NouvelleLane({required this.projet, required this.graphe});
  final ProjetPerso projet;
  final GrapheProjet? graphe;

  @override
  State<_NouvelleLane> createState() => _NouvelleLaneState();
}

class _NouvelleLaneState extends State<_NouvelleLane> {
  final nom = TextEditingController();
  final consigne = TextEditingController();
  late final TextEditingController dossier;
  String agent = 'opencode';
  String? parent;
  bool envoi = false;
  String? erreur;

  /// Nœuds auxquels relier la lane : ceux du graphe (orchestrateur en premier).
  late final List<Map<String, dynamic>> parents;

  @override
  void initState() {
    super.initState();
    dossier = TextEditingController(text: widget.projet.dossier ?? '');
    final sessions = widget.graphe?.sessions ?? widget.projet.sessions;
    final aUnParent = {for (final l in widget.graphe?.liens ?? const []) l.vers};
    int rang(Map<String, dynamic> s) {
      final orch = nomDe(s).toLowerCase().contains('orch');
      final racine = !aUnParent.contains(s['id'].toString());
      return (orch ? 0 : 2) + (racine ? 0 : 1);
    }

    parents = [...sessions]..sort((a, b) => rang(a).compareTo(rang(b)));
    if (parents.isNotEmpty) parent = parents.first['id'].toString();
  }

  @override
  void dispose() {
    nom.dispose();
    consigne.dispose();
    dossier.dispose();
    super.dispose();
  }

  Future<void> _lancer() async {
    final n = nom.text.trim(), c = consigne.text.trim();
    if (n.isEmpty || c.isEmpty) {
      setState(() => erreur = 'Donne un nom et une consigne.');
      return;
    }
    setState(() {
      envoi = true;
      erreur = null;
    });
    try {
      final r = await lancerLanePc(
        projet: widget.projet.nom,
        dossier: dossier.text.trim().isEmpty ? null : dossier.text.trim(),
        nom: n,
        consigne: c,
        agent: agent,
        orchestrateurId: parent,
      );
      if (mounted) Navigator.of(context).pop(r['session_id']?.toString() ?? '');
    } catch (e) {
      if (mounted) {
        setState(() {
          envoi = false;
          erreur = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: PaletteN8n.lien,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const BlocIcone(
                  icone: Icons.add_rounded, couleur: PaletteN8n.accent, taille: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nouvelle lane', style: TexteN8n.sousTitre),
                      Text(widget.projet.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TexteN8n.doux),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('AGENT', style: TexteN8n.etiquette),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'opencode',
                    label: Text('OpenCode'),
                    icon: Icon(Icons.terminal_rounded)),
                ButtonSegment(
                    value: 'claude',
                    label: Text('Claude Code'),
                    icon: Icon(Icons.auto_awesome_rounded)),
              ],
              selected: {agent},
              onSelectionChanged: envoi ? null : (v) => setState(() => agent = v.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nom,
              enabled: !envoi,
              style: TexteN8n.corps,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Nom',
                  hintText: 'Lane TRAD : traduction des codes défaut'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: consigne,
              enabled: !envoi,
              minLines: 3,
              maxLines: 8,
              style: TexteN8n.corps,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Consigne',
                  hintText: 'Objectif, fichiers concernés, quand s\'arrêter…',
                  alignLabelWithHint: true),
            ),
            if (parents.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: parent,
                isExpanded: true,
                dropdownColor: PaletteN8n.carteHaut,
                style: TexteN8n.corps,
                decoration: const InputDecoration(labelText: 'Reliée à'),
                items: [
                  for (final s in parents)
                    DropdownMenuItem(
                      value: s['id'].toString(),
                      child: Text(nomDe(s),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: envoi ? null : (v) => setState(() => parent = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: dossier,
              enabled: !envoi,
              style: TexteN8n.corps.copyWith(fontSize: 13),
              decoration: const InputDecoration(
                  labelText: 'Dossier sur le PC',
                  helperText: 'Laisse tel quel : dossier du projet.'),
            ),
            if (erreur != null) ...[
              const SizedBox(height: 10),
              Text(erreur!,
                  style: TexteN8n.doux.copyWith(color: PaletteN8n.rouge)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              onPressed: envoi ? null : _lancer,
              icon: envoi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.rocket_launch_rounded),
              label: Text(envoi
                  ? 'Lancement sur le PC… (jusqu\'à 2 min)'
                  : 'Lancer la lane'),
            ),
          ],
        ),
      ),
    );
  }
}
