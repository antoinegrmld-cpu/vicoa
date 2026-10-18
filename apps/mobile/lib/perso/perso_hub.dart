// Vicoa Perso — liens entre agents d'un projet (orchestrateur -> sous-agents).
//
// Vicoa ne connaît pas de lien parent/enfant entre sessions. Deux sources, dans l'ordre :
//  1. un fichier `hub.json` à la racine du dossier du projet, lu sur le PC via le démon
//     Vicoa (RPC read-file, déjà utilisé par l'écran Fichiers de l'appli) :
//       {
//         "orchestrateur": "ORCH diag-auto",              // nom (ou morceau du nom) ou id de session
//         "liens": [ {"de": "ORCH diag-auto", "vers": "lane FIAB"} ]   // facultatif
//       }
//     Sans "liens", l'orchestrateur pointe vers toutes les autres sessions du projet.
//  2. sinon, une règle simple : une session dont le nom contient « orch » est l'orchestrateur.
//  3. en plus, les LANES détectées sur le PC par le service d'import (C:\hub-agents\vicoa-import\hubs\<projet>.json) :
//     chaque lane lancée par l'orchestrateur apparaît (même hors de Vicoa) et est reliée au nœud orchestrateur.

import 'dart:convert';

import '/custom_code/actions/index.dart' as actions;
import 'perso_store.dart';

class LienAgent {
  const LienAgent(this.de, this.vers);
  final String de; // id de session
  final String vers;
}

class GrapheProjet {
  GrapheProjet(this.sessions, this.liens, this.source);
  final List<Map<String, dynamic>> sessions;
  final List<LienAgent> liens;
  final String source; // 'hub.json', 'règle « orch »' ou 'aucun lien'
}

/// Lit un fichier texte sur le PC (via le démon Vicoa). Renvoie null s'il n'existe pas.
Future<String?> lireFichierPc(
    String machineId, String dossier, String chemin) async {
  final r = await actions.VicoaWsClient.instance
      .callRpc(machineId, 'read-file', {'cwd': dossier, 'path': chemin});
  if (r['error'] != null) return null;
  return r['content']?.toString();
}

/// Écrit un fichier texte sur le PC (via le démon Vicoa). Renvoie l'erreur éventuelle.
Future<String?> ecrireFichierPc(
    String machineId, String dossier, String chemin, String contenu) async {
  final r = await actions.VicoaWsClient.instance.callRpc(
      machineId,
      'write-file',
      {'cwd': dossier, 'path': chemin, 'content': contenu, 'force': true});
  return r['error']?.toString();
}

String? _trouver(List<Map<String, dynamic>> sessions, String? ref) {
  if (ref == null || ref.trim().isEmpty) return null;
  final r = ref.trim().toLowerCase();
  for (final s in sessions) {
    if (s['id'].toString().toLowerCase() == r) return s['id'].toString();
  }
  for (final s in sessions) {
    if (nomDe(s).toLowerCase().contains(r)) return s['id'].toString();
  }
  return null;
}

Future<GrapheProjet> _grapheDeBase(ProjetPerso projet) async {
  final sessions = List<Map<String, dynamic>>.from(projet.sessions)
    ..sort((a, b) => nomDe(a).compareTo(nomDe(b)));
  final machine = projet.machineId, dossier = projet.dossier;

  // 1. hub.json
  if (machine != null && dossier != null) {
    try {
      final texte = await lireFichierPc(machine, dossier, 'hub.json');
      if (texte != null) {
        final hub = jsonDecode(texte);
        if (hub is Map) {
          final liens = <LienAgent>[];
          final orch = _trouver(sessions, hub['orchestrateur']?.toString());
          final brut = hub['liens'];
          if (brut is List) {
            for (final l in brut.whereType<Map>()) {
              final de = _trouver(sessions, l['de']?.toString());
              final vers = _trouver(sessions, l['vers']?.toString());
              if (de != null && vers != null && de != vers) {
                liens.add(LienAgent(de, vers));
              }
            }
          } else if (orch != null) {
            for (final s in sessions) {
              if (s['id'].toString() != orch) {
                liens.add(LienAgent(orch, s['id'].toString()));
              }
            }
          }
          return GrapheProjet(sessions, liens, 'hub.json');
        }
      }
    } catch (_) {
      // PC éteint, fichier illisible... : on passe à la règle simple.
    }
  }

  // 2. règle « orch »
  final orchs = sessions
      .where((s) => nomDe(s).toLowerCase().contains('orch'))
      .map((s) => s['id'].toString())
      .toList();
  if (orchs.isNotEmpty) {
    final principal = orchs.first;
    final liens = [
      for (final s in sessions)
        if (s['id'].toString() != principal)
          LienAgent(principal, s['id'].toString()),
    ];
    return GrapheProjet(sessions, liens, 'règle « orch »');
  }
  return GrapheProjet(sessions, const [], 'aucun lien');
}

/// Dossier du PC où le service d'import écrit les lanes détectées (hubs\<projet>.json).
const String kDossierImportPc = r'C:\hub-agents\vicoa-import';

String _nomDossier(String chemin) =>
    chemin.replaceAll('/', r'\').split(r'\').where((x) => x.isNotEmpty).last;

/// Graphe du projet : sessions Vicoa + lanes détectées sur le PC, reliées à l'orchestrateur.
Future<GrapheProjet> construireGraphe(ProjetPerso projet) async {
  final base = await _grapheDeBase(projet);
  final machine = projet.machineId ?? PersoStore.instance.machineEnLigne();
  if (machine == null) return base;
  final noms = <String>{
    if (projet.dossier != null) _nomDossier(projet.dossier!),
    projet.nom,
  };
  for (final nom in noms) {
    try {
      final texte =
          await lireFichierPc(machine, kDossierImportPc, 'hubs/$nom.json');
      if (texte == null) continue;
      final hub = jsonDecode(texte);
      if (hub is Map) return _ajouterLanes(base, hub);
    } catch (_) {
      // PC injoignable : on garde le graphe de base
    }
  }
  return base;
}

/// Nœud pour une session qui tourne sur le PC mais n'est pas (encore) dans Vicoa.
Map<String, dynamic> _noeudExterne(Map e) => {
      'id': 'ext:${e['agent']}:${e['id']}',
      'name': e['titre'],
      'agent_type_name': e['agent'] == 'opencode' ? 'OpenCode' : 'Claude Code',
      'status': e['etat'] ?? 'COMPLETED',
      'session_config': {'model': 'sur le PC'},
      'latest_message_at': e['derniere_activite'],
      'externe': true,
      'agent_externe': e['agent'],
      'session_externe': e['id'],
      'dossier': e['dossier'],
      'resume': e['resume'] ?? '',
    };

GrapheProjet _ajouterLanes(GrapheProjet base, Map hub) {
  final sessions = List<Map<String, dynamic>>.from(base.sessions);
  final liens = List<LienAgent>.from(base.liens);
  final ids = {for (final s in sessions) s['id'].toString()};
  String? dansVicoa(Map e) {
    final v = e['vicoa_id']?.toString();
    return v != null && ids.contains(v) ? v : null;
  }

  // Orchestrateur : sa session Vicoa si elle a été importée, sinon celui du graphe de base, sinon un nœud « PC ».
  String? orch;
  final o = hub['orchestrateur'];
  if (o is Map) orch = dansVicoa(o);
  orch ??= base.liens.isNotEmpty ? base.liens.first.de : null;
  if (orch == null && o is Map) {
    final n = _noeudExterne(o);
    sessions.add(n);
    orch = n['id'] as String;
  }

  final lanes = hub['lanes'];
  if (lanes is List) {
    for (final l in lanes.whereType<Map>()) {
      var id = dansVicoa(l);
      if (id == null) {
        final n = _noeudExterne(l);
        id = n['id'] as String;
        if (!sessions.any((s) => s['id'] == id)) sessions.add(n);
      }
      if (orch != null &&
          id != orch &&
          !liens.any((x) => x.de == orch && x.vers == id)) {
        liens.add(LienAgent(orch, id));
      }
    }
  }
  return GrapheProjet(sessions, liens, 'lanes du PC');
}

/// Disposition façon n8n : le flux se lit de gauche à droite.
/// Colonne 0 = orchestrateurs, colonne 1 = leurs sous-agents, etc.
/// Les sessions sans lien sont rangées à droite, en colonnes de 6.
class DispositionGraphe {
  static const double largeurNoeud = 230;
  static const double hauteurNoeud = 80;
  static const double ecartX = 110; // place pour les courbes
  static const double ecartY = 34;
  static const double marge = 60;
  static const int parColonneIsoles = 6;

  DispositionGraphe(GrapheProjet g) {
    final ids = [for (final s in g.sessions) s['id'].toString()];
    final enfants = <String, List<String>>{};
    final aUnParent = <String>{};
    for (final l in g.liens) {
      enfants.putIfAbsent(l.de, () => []).add(l.vers);
      aUnParent.add(l.vers);
    }
    final colonne = <String, int>{};
    final racines = ids
        .where((id) => !aUnParent.contains(id) && enfants.containsKey(id))
        .toList();
    final file = <String>[...racines];
    for (final r in racines) {
      colonne[r] = 0;
    }
    while (file.isNotEmpty) {
      final id = file.removeAt(0);
      for (final e in enfants[id] ?? const <String>[]) {
        if (!colonne.containsKey(e)) {
          colonne[e] = colonne[id]! + 1;
          file.add(e);
        }
      }
    }
    // Sessions sans lien : colonnes de 6, à droite du flux.
    final isoles = ids.where((id) => !colonne.containsKey(id)).toList();
    final premiereLibre = colonne.isEmpty
        ? 0
        : colonne.values.reduce((a, b) => a > b ? a : b) + 1;
    for (var i = 0; i < isoles.length; i++) {
      colonne[isoles[i]] = premiereLibre + i ~/ parColonneIsoles;
    }
    final parColonne = <int, List<String>>{};
    for (final id in ids) {
      parColonne.putIfAbsent(colonne[id]!, () => []).add(id);
    }
    final hauteurMax = parColonne.values
        .map((l) => l.length * (hauteurNoeud + ecartY) - ecartY)
        .fold<double>(0, (a, b) => a > b ? a : b);
    for (final entree in parColonne.entries) {
      final liste = entree.value;
      final hauteurColonne = liste.length * (hauteurNoeud + ecartY) - ecartY;
      final y0 = marge + (hauteurMax - hauteurColonne) / 2;
      for (var i = 0; i < liste.length; i++) {
        positions[liste[i]] = (
          x: marge + entree.key * (largeurNoeud + ecartX),
          y: y0 + i * (hauteurNoeud + ecartY),
        );
      }
    }
    final nbColonnes =
        parColonne.keys.fold<int>(0, (a, b) => a > b ? a : b) + 1;
    largeur = marge * 2 + nbColonnes * (largeurNoeud + ecartX) - ecartX;
    hauteur = marge * 2 + hauteurMax;
  }

  final Map<String, ({double x, double y})> positions = {};
  late final double largeur;
  late final double hauteur;
}
