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
  var graphe = base;
  for (final nom in noms) {
    try {
      final texte =
          await lireFichierPc(machine, kDossierImportPc, 'hubs/$nom.json');
      if (texte == null) continue;
      final hub = jsonDecode(texte);
      if (hub is Map) {
        graphe = _ajouterLanes(base, hub);
        break;
      }
    } catch (_) {
      // PC injoignable : on garde le graphe de base
    }
  }
  return _appliquerLiensAgents(graphe, machine);
}

/// Liens posés par les agents eux-mêmes (outil « vicoa » du hub : vicoa_lancer_lane, vicoa_relier)
/// et lanes qu'ils ont retirées (vicoa_supprimer) : C:\hub-agents\vicoa-import\liens.json.
Future<GrapheProjet> _appliquerLiensAgents(
    GrapheProjet g, String machine) async {
  try {
    final texte = await lireFichierPc(machine, kDossierImportPc, 'liens.json');
    if (texte == null) return g;
    final d = jsonDecode(texte);
    if (d is! Map) return g;
    final masques = {
      ...(d['masques'] as List? ?? const []).map((x) => x.toString())
    };
    final sessions =
        g.sessions.where((s) => !masques.contains(s['id'].toString())).toList();
    final ids = {for (final s in sessions) s['id'].toString()};
    final liens = g.liens
        .where((l) => ids.contains(l.de) && ids.contains(l.vers))
        .toList();
    for (final l in (d['liens'] as List? ?? const []).whereType<Map>()) {
      final de = l['de']?.toString(), vers = l['vers']?.toString();
      if (de == null ||
          vers == null ||
          !ids.contains(de) ||
          !ids.contains(vers)) {
        continue;
      }
      // Un lien explicite remplace le lien « automatique » vers la même lane.
      liens.removeWhere((x) => x.vers == vers);
      liens.add(LienAgent(de, vers));
    }
    return GrapheProjet(sessions, liens, g.source);
  } catch (_) {
    return g;
  }
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

/// Disposition en MINDMAP : l'orchestrateur au centre, ses lanes en branches à droite ET à gauche
/// (réparties pour équilibrer), les sous-lanes plus loin sur la même branche. Plusieurs orchestrateurs :
/// plusieurs mindmaps empilées. Les sessions sans lien : une rangée en dessous.
class DispositionGraphe {
  static const double largeurNoeud = 230;
  static const double hauteurNoeud = 80;
  static const double ecartX = 110; // place pour les courbes
  static const double ecartY = 26;
  static const double marge = 60;
  static const double ecartCartes =
      90; // entre deux mindmaps, et avant les sessions isolées
  static const int parLigneIsoles = 3;

  DispositionGraphe(GrapheProjet g) {
    final ids = [for (final s in g.sessions) s['id'].toString()];
    final enfants = <String, List<String>>{};
    final aUnParent = <String>{};
    for (final l in g.liens) {
      if (l.de == l.vers) continue;
      enfants.putIfAbsent(l.de, () => []).add(l.vers);
      aUnParent.add(l.vers);
    }
    var racines = ids
        .where((id) => !aUnParent.contains(id) && enfants.containsKey(id))
        .toList();
    if (racines.isEmpty && g.liens.isNotEmpty) {
      racines = [g.liens.first.de]; // cas d'une boucle
    }

    const pasY = hauteurNoeud + ecartY, pasX = largeurNoeud + ecartX;
    final places = <String>{};
    var yCarte = 0.0; // haut de la mindmap en cours (coordonnées relatives)
    final relatives = <String, ({double x, double y})>{};

    // Feuilles d'une branche (pour équilibrer et répartir verticalement).
    int feuilles(String id, Set<String> vus) {
      if (!vus.add(id)) return 0;
      final e = (enfants[id] ?? const <String>[])
          .where((x) => !vus.contains(x))
          .toList();
      if (e.isEmpty) return 1;
      return e.fold<int>(0, (a, c) => a + feuilles(c, vus)).clamp(1, 1 << 30);
    }

    // Place une branche ; renvoie le y (centre) du nœud. `cote` = +1 droite, -1 gauche.
    double placer(String id, int profondeur, int cote, double yHaut) {
      places.add(id);
      final e = (enfants[id] ?? const <String>[])
          .where((x) => !places.contains(x))
          .toList();
      final x = cote * profondeur * pasX;
      if (e.isEmpty) {
        relatives[id] = (x: x, y: yHaut);
        return yHaut;
      }
      var y = yHaut;
      final centres = <double>[];
      for (final c in e) {
        final n = feuilles(c, {...places});
        centres.add(placer(c, profondeur + 1, cote, y));
        y += n * pasY;
      }
      final centre = (centres.first + centres.last) / 2;
      relatives[id] = (x: x, y: centre);
      return centre;
    }

    for (final r in racines) {
      if (places.contains(r)) continue;
      places.add(r);
      final branches = (enfants[r] ?? const <String>[])
          .where((x) => !places.contains(x))
          .toList()
        ..sort((a, b) => feuilles(b, {r}).compareTo(feuilles(a, {r})));
      // Répartition équilibrée : chaque branche va du côté le moins chargé (droite d'abord).
      final droite = <String>[], gauche = <String>[];
      var chargeD = 0, chargeG = 0;
      for (final b in branches) {
        final n = feuilles(b, {r});
        if (chargeD <= chargeG) {
          droite.add(b);
          chargeD += n;
        } else {
          gauche.add(b);
          chargeG += n;
        }
      }
      final hauteurD = chargeD * pasY, hauteurG = chargeG * pasY;
      final hauteur =
          [hauteurD, hauteurG, pasY].reduce((a, b) => a > b ? a : b);
      var y = yCarte + (hauteur - hauteurD) / 2;
      for (final b in droite) {
        final n = feuilles(b, {...places});
        placer(b, 1, 1, y);
        y += n * pasY;
      }
      y = yCarte + (hauteur - hauteurG) / 2;
      for (final b in gauche) {
        final n = feuilles(b, {...places});
        placer(b, 1, -1, y);
        y += n * pasY;
      }
      relatives[r] = (x: 0, y: yCarte + hauteur / 2 - pasY / 2);
      yCarte += hauteur + ecartCartes;
    }

    // Sessions sans lien : rangées sous les mindmaps, centrées.
    final isoles = ids.where((id) => !relatives.containsKey(id)).toList();
    for (var i = 0; i < isoles.length; i++) {
      final col = i % parLigneIsoles, ligne = i ~/ parLigneIsoles;
      final nbCol =
          isoles.length < parLigneIsoles ? isoles.length : parLigneIsoles;
      relatives[isoles[i]] =
          (x: (col - (nbCol - 1) / 2) * pasX, y: yCarte + ligne * pasY);
    }

    // Passage en coordonnées positives (avec marge).
    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
    var premier = true;
    for (final p in relatives.values) {
      if (premier) {
        minX = maxX = p.x;
        minY = maxY = p.y;
        premier = false;
      }
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    relatives.forEach((id, p) =>
        positions[id] = (x: p.x - minX + marge, y: p.y - minY + marge));
    largeur = maxX - minX + largeurNoeud + 2 * marge;
    hauteur = maxY - minY + hauteurNoeud + 2 * marge;
    centre = racines.isNotEmpty && positions[racines.first] != null
        ? (
            x: positions[racines.first]!.x + largeurNoeud / 2,
            y: positions[racines.first]!.y + hauteurNoeud / 2
          )
        : (x: largeur / 2, y: hauteur / 2);
  }

  final Map<String, ({double x, double y})> positions = {};
  late final double largeur;
  late final double hauteur;

  /// Centre du nœud orchestrateur (pour cadrer la vue sur lui).
  late final ({double x, double y}) centre;
}
