// Vicoa Perso — import des sessions OpenCode / Claude Code du PC, en 3 temps :
//   1. tu coches les sessions (liste lue sur le PC : catalogue.json) ;
//   2. abliterated (OpenCode) propose titre + projet, tu corriges si besoin ;
//   3. tu confirmes, le service du PC importe.
// Dialogue par fichiers dans C:\hub-agents\vicoa-import, via le démon Vicoa (RPC read-file / write-file).
// Côté PC : C:\hub-agents\vicoa-import\service_import.py (lancé au démarrage de Windows).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'perso_commun.dart';
import 'perso_hub.dart' show ecrireFichierPc, lireFichierPc;
import 'perso_store.dart';
import 'perso_theme.dart';

const String kDossierImport = r'C:\hub-agents\vicoa-import';

class ImportPersoWidget extends StatefulWidget {
  const ImportPersoWidget({super.key});

  static String routeName = 'ImportPerso';
  static String routePath = '/perso/import';

  @override
  State<ImportPersoWidget> createState() => _ImportPersoWidgetState();
}

enum _Etape { choix, attente, proposition, resultat }

class _ImportPersoWidgetState extends State<ImportPersoWidget> {
  final store = PersoStore.instance;
  _Etape etape = _Etape.choix;
  String? machine, erreur, majCatalogue, messageAttente;
  List<Map<String, dynamic>> catalogue = [];
  final Set<String> coches = {};
  bool masquerImportees = true;
  String filtreAgent = 'tous';
  String? demandeId;
  List<Map<String, dynamic>> proposition = [];
  List<Map<String, dynamic>> resultats = [];
  final Map<String, TextEditingController> titres = {}, projets = {};
  Timer? _attente;

  @override
  void initState() {
    super.initState();
    store.ouvrir();
    _chargerCatalogue();
  }

  @override
  void dispose() {
    _attente?.cancel();
    for (final c in [...titres.values, ...projets.values]) {
      c.dispose();
    }
    store.fermer();
    super.dispose();
  }

  String _cle(Map s) => '${s['agent']}|${s['id']}';

  Future<void> _chargerCatalogue() async {
    setState(() => erreur = null);
    if (store.machines.isEmpty) await store.charger();
    machine = store.machineEnLigne();
    if (machine == null) {
      setState(() => erreur =
          'Aucun PC relié à Vicoa. Vérifie que « vicoa daemon » tourne.');
      return;
    }
    try {
      final texte =
          await lireFichierPc(machine!, kDossierImport, 'catalogue.json');
      if (texte == null) {
        setState(() => erreur =
            "Liste des sessions introuvable sur le PC. Le service d'import tourne-t-il ? "
                '(raccourci « Vicoa » du dossier Démarrage)');
        return;
      }
      final d = jsonDecode(texte) as Map;
      setState(() {
        catalogue = (d['sessions'] as List)
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
        majCatalogue = d['mis_a_jour']?.toString();
      });
    } catch (e) {
      setState(() => erreur = 'Lecture impossible : $e');
    }
  }

  Future<void> _ecrireDemande(Map<String, dynamic> d) async {
    final err = await ecrireFichierPc(
        machine!,
        kDossierImport,
        'demandes/$demandeId.json',
        const JsonEncoder.withIndent('  ').convert(d));
    if (err != null) throw Exception(err);
  }

  /// Relit la demande toutes les 3 s jusqu'à ce que le service du PC ait répondu.
  void _attendre(
      Set<String> etatsFinaux, void Function(Map<String, dynamic>) quandPret) {
    _attente?.cancel();
    _attente = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final texte = await lireFichierPc(
            machine!, kDossierImport, 'demandes/$demandeId.json');
        if (texte == null) return;
        final d = Map<String, dynamic>.from(jsonDecode(texte) as Map);
        if (d['etat'] == 'erreur') {
          timer.cancel();
          setState(() {
            erreur = 'Le PC signale une erreur : ${d['erreur']}';
            etape = _Etape.choix;
          });
        } else if (etatsFinaux.contains(d['etat'])) {
          timer.cancel();
          quandPret(d);
        } else if (mounted) {
          setState(() => messageAttente = d['etat'] == 'reflexion'
              ? 'abliterated réfléchit au rangement…'
              : d['etat'] == 'en_cours'
                  ? 'Import en cours sur le PC…'
                  : 'En attente du PC…');
        }
      } catch (_) {/* on réessaie au prochain tour */}
    });
  }

  Future<void> _proposer() async {
    demandeId = 'demande-${DateTime.now().millisecondsSinceEpoch}';
    final choisies = catalogue.where((s) => coches.contains(_cle(s))).toList();
    setState(() {
      etape = _Etape.attente;
      messageAttente = 'Envoi de ta sélection au PC…';
      erreur = null;
    });
    try {
      await _ecrireDemande({
        'etat': 'selection',
        'organiser': true,
        'sessions': [
          for (final s in choisies) {'agent': s['agent'], 'id': s['id']}
        ],
      });
    } catch (e) {
      setState(() {
        erreur = 'Envoi impossible : $e';
        etape = _Etape.choix;
      });
      return;
    }
    _attendre({'proposition'}, (d) {
      proposition = (d['proposition'] as List)
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      for (final p in proposition) {
        titres[p['id']] =
            TextEditingController(text: p['titre']?.toString() ?? '');
        projets[p['id']] =
            TextEditingController(text: p['projet']?.toString() ?? '');
      }
      setState(() => etape = _Etape.proposition);
    });
  }

  Future<void> _confirmer() async {
    for (final p in proposition) {
      p['titre'] = titres[p['id']]!.text.trim();
      p['projet'] = projets[p['id']]!.text.trim();
    }
    setState(() {
      etape = _Etape.attente;
      messageAttente = 'Import en cours sur le PC…';
    });
    try {
      await _ecrireDemande({
        'etat': 'confirmation',
        'organiser': true,
        'proposition': proposition
      });
    } catch (e) {
      setState(() {
        erreur = 'Envoi impossible : $e';
        etape = _Etape.proposition;
      });
      return;
    }
    _attendre({'termine'}, (d) {
      resultats = (d['resultats'] as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      setState(() => etape = _Etape.resultat);
      store.charger();
    });
  }

  @override
  Widget build(BuildContext context) {
    const t = _Couleurs();
    return Theme(
      data: themeN8n(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Importer des sessions'),
          actions: [
            if (etape == _Etape.choix)
              IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _chargerCatalogue),
          ],
        ),
        body: Column(children: [
          if (erreur != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: t.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(erreur!, style: t.bodySmall.copyWith(color: t.error)),
            ),
          Expanded(
              child: switch (etape) {
            _Etape.choix => _choix(context),
            _Etape.attente => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(messageAttente ?? '', style: t.bodyMedium),
                ]),
              ),
            _Etape.proposition => _proposition(context),
            _Etape.resultat => _resultat(context),
          }),
        ]),
      ),
    );
  }

  Widget _choix(BuildContext context) {
    const t = _Couleurs();
    final visibles = catalogue.where((s) {
      if (masquerImportees && s['deja_importee'] == true) return false;
      if (filtreAgent != 'tous' && s['agent'] != filtreAgent) return false;
      return true;
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in const [
                ('tous', 'Toutes'),
                ('opencode', 'OpenCode'),
                ('claude-code', 'Claude Code')
              ])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: filtreAgent == f.$1,
                  onSelected: (_) => setState(() => filtreAgent = f.$1),
                ),
              FilterChip(
                label: const Text('Masquer les déjà importées'),
                selected: masquerImportees,
                onSelected: (v) => setState(() => masquerImportees = v),
              ),
            ]),
      ),
      if (majCatalogue != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Liste du PC mise à jour : $majCatalogue',
              style: t.labelSmall.copyWith(color: t.secondaryText)),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: visibles.length,
          itemBuilder: (context, i) {
            final s = visibles[i];
            final cle = _cle(s);
            final active = s['active_recemment'] == true;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: CarteN8n(
                accent: coches.contains(cle) ? PaletteN8n.accent : null,
                child: CheckboxListTile(
                  value: coches.contains(cle),
                  onChanged: (v) => setState(
                      () => v == true ? coches.add(cle) : coches.remove(cle)),
                  title: Text(s['titre']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium),
                  subtitle: Text(
                    '${s['agent'] == 'opencode' ? 'OpenCode' : 'Claude Code'} · '
                    '${ilYA(DateTime.tryParse(s['derniere_activite']?.toString() ?? ''))}'
                    '${active ? ' · ⚠ utilisée en ce moment' : ''}'
                    '${s['deja_importee'] == true ? ' · déjà importée' : ''}\n${s['dossier'] ?? ''}',
                    maxLines: 3,
                    style: t.labelSmall
                        .copyWith(color: active ? t.warning : t.secondaryText),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: coches.isEmpty || machine == null ? null : _proposer,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(coches.isEmpty
                  ? 'Coche les sessions à importer'
                  : 'Demander une proposition (${coches.length})'),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _proposition(BuildContext context) {
    const t = _Couleurs();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          "Proposition d'abliterated. Corrige les titres ou les projets si besoin, puis confirme. "
          "Les sessions Claude Code deviennent des tâches (résumé + commande pour les reprendre).",
          style: t.bodySmall.copyWith(color: t.secondaryText),
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: proposition.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final p = proposition[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.primaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.alternate),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        p['agent'] == 'opencode'
                            ? 'OpenCode → session Vicoa'
                            : 'Claude Code → tâche Vicoa',
                        style: t.labelSmall.copyWith(color: t.secondaryText)),
                    TextField(
                        controller: titres[p['id']],
                        decoration: const InputDecoration(labelText: 'Titre')),
                    TextField(
                        controller: projets[p['id']],
                        decoration: const InputDecoration(labelText: 'Projet')),
                    if ((p['resume'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(p['resume'].toString(),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall),
                      ),
                  ]),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            TextButton(
              onPressed: () => setState(() => etape = _Etape.choix),
              child: const Text('Annuler'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _confirmer,
              icon: const Icon(Icons.check_rounded),
              label: Text("Confirmer l'import (${proposition.length})"),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _resultat(BuildContext context) {
    const t = _Couleurs();
    final ok = resultats.where((r) => r['ok'] == true).length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text('$ok import(s) réussi(s) sur ${resultats.length}.',
            style: t.titleMedium),
      ),
      Expanded(
        child: ListView(children: [
          for (final r in resultats)
            ListTile(
              leading: Icon(
                  r['ok'] == true
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color: r['ok'] == true ? t.success : t.error),
              title: Text(
                  proposition
                      .firstWhere((p) => p['id'] == r['id'],
                          orElse: () => {'titre': r['id']})['titre']
                      .toString(),
                  style: t.bodyMedium),
              subtitle: Text(
                  r['ok'] == true ? 'Importée' : (r['detail'] ?? '').toString(),
                  maxLines: 3,
                  style: t.labelSmall),
            ),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () {
              coches.clear();
              setState(() => etape = _Etape.choix);
              _chargerCatalogue();
            },
            child: const Text('Importer d\'autres sessions'),
          ),
        ),
      ),
    ]);
  }
}

/// Couleurs et textes de l'écran, branchés sur la palette sombre façon n8n.
class _Couleurs {
  const _Couleurs();
  Color get secondaryBackground => PaletteN8n.fond;
  Color get primaryBackground => PaletteN8n.carte;
  Color get alternate => PaletteN8n.bord;
  Color get secondaryText => PaletteN8n.texteDoux;
  Color get error => PaletteN8n.rouge;
  Color get warning => PaletteN8n.orange;
  Color get success => PaletteN8n.vert;
  TextStyle get titleMedium => TexteN8n.sousTitre;
  TextStyle get bodyMedium => TexteN8n.corps;
  TextStyle get bodySmall => TexteN8n.corps.copyWith(fontSize: 13);
  TextStyle get labelSmall => TexteN8n.doux;
}
