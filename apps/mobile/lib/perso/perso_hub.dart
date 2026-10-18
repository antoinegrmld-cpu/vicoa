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
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

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

/// Disposition en MINDMAP RADIALE : l'orchestrateur au centre, ses lanes réparties TOUT AUTOUR (haut, droite,
/// bas, gauche...). Les sous-lanes partent vers l'extérieur de leur lane : en colonne pour une branche de côté,
/// en rangée pour une branche du haut ou du bas (comme une mindmap « CQQCOQP »). Liaisons à angles droits
/// arrondis (accolades). Plusieurs orchestrateurs : plusieurs mindmaps côte à côte ; sessions sans lien : en dessous.
class DispositionGraphe {
  static const double largeurNoeud = 230;
  static const double hauteurNoeud = 80;
  static const double ecartGroupe = 70; // entre une lane et ses sous-lanes
  static const double ecartFrere = 22; // entre deux sous-lanes voisines
  static const double ecartCartes = 160; // entre deux mindmaps
  static const double marge = 60;
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

    const w = largeurNoeud, h = hauteurNoeud;
    final places = <String>{};
    final rel = <String,
        Offset>{}; // coin haut-gauche, relatif au centre de la mindmap en cours
    final orientations = <String,
        Offset>{}; // direction de croissance d'une branche (+-1, 0) ou (0, +-1)
    var decalageX = 0.0;

    // Sous-lanes d'un nœud, vers l'extérieur ; renvoie les rectangles occupés (pour éviter les chevauchements).
    void placerGroupe(String parent, Offset dir, List<Rect> occupes) {
      final e = (enfants[parent] ?? const <String>[])
          .where((x) => !places.contains(x))
          .toList();
      if (e.isEmpty) return;
      places.addAll(e);
      final p = rel[parent]!;
      for (var i = 0; i < e.length; i++) {
        final Offset coin;
        if (dir.dx != 0) {
          // branche de côté : colonne de sous-lanes, centrée sur le parent
          final total = e.length * h + (e.length - 1) * ecartFrere;
          coin = Offset(p.dx + dir.dx * (w + ecartGroupe),
              p.dy + h / 2 - total / 2 + i * (h + ecartFrere));
        } else {
          // branche du haut ou du bas : rangée de sous-lanes, centrée sur le parent
          final total = e.length * w + (e.length - 1) * ecartFrere;
          coin = Offset(p.dx + w / 2 - total / 2 + i * (w + ecartFrere),
              p.dy + dir.dy * (h + ecartGroupe));
        }
        rel[e[i]] = coin;
        orientations[e[i]] = dir;
        occupes.add(coin & const Size(w, h));
        placerGroupe(e[i], dir, occupes);
      }
    }

    for (final r in racines) {
      if (places.contains(r)) continue;
      places.add(r);
      final branches = (enfants[r] ?? const <String>[])
          .where((x) => !places.contains(x))
          .toList();
      places.addAll(branches);
      final n = branches.length;
      // Rayons de départ, puis agrandis jusqu'à ce que plus rien ne se chevauche.
      var rx = (w + 90).toDouble() + n * 22, ry = (h + 110).toDouble() + n * 14;
      Map<String, Offset> essai = {};
      for (var tentative = 0; tentative < 60; tentative++) {
        essai = {r: const Offset(-w / 2, -h / 2)};
        final occupes = <Rect>[essai[r]! & const Size(w, h)];
        final sauvePlaces = {...places};
        rel
          ..clear()
          ..addAll(essai);
        for (var k = 0; k < n; k++) {
          // de midi (en haut) dans le sens des aiguilles d'une montre
          final angle = -math.pi / 2 + 2 * math.pi * k / n;
          final cx = rx * math.cos(angle), cy = ry * math.sin(angle);
          rel[branches[k]] = Offset(cx - w / 2, cy - h / 2);
          final dir = math.cos(angle).abs() >= math.sin(angle).abs() * 0.9
              ? Offset(math.cos(angle) >= 0 ? 1 : -1, 0)
              : Offset(0, math.sin(angle) >= 0 ? 1 : -1);
          orientations[branches[k]] = dir;
          occupes.add(rel[branches[k]]! & const Size(w, h));
          placerGroupe(branches[k], dir, occupes);
        }
        var chevauche = false;
        for (var i = 0; i < occupes.length && !chevauche; i++) {
          for (var j = i + 1; j < occupes.length; j++) {
            if (occupes[i]
                .inflate(ecartFrere / 2)
                .overlaps(occupes[j].inflate(ecartFrere / 2))) {
              chevauche = true;
              break;
            }
          }
        }
        if (!chevauche) break;
        // on recommence plus grand
        places
          ..clear()
          ..addAll(sauvePlaces);
        rx *= 1.12;
        ry *= 1.12;
      }
      // Recadrage de cette mindmap à droite des précédentes.
      final cles =
          rel.keys.where((k) => !positionsBrutes.containsKey(k)).toList();
      var minX = double.infinity;
      for (final k in cles) {
        minX = math.min(minX, rel[k]!.dx);
      }
      for (final k in cles) {
        positionsBrutes[k] = rel[k]! + Offset(decalageX - minX, 0);
      }
      var maxX = -double.infinity;
      for (final k in cles) {
        maxX = math.max(maxX, positionsBrutes[k]!.dx + w);
      }
      decalageX = maxX + ecartCartes;
      if (racines.first == r) {
        centreBrut = positionsBrutes[r]! + const Offset(w / 2, h / 2);
      }
    }

    // Sessions sans lien : rangées sous les mindmaps.
    var basY = 0.0;
    for (final p in positionsBrutes.values) {
      basY = math.max(basY, p.dy + h);
    }
    final isoles = ids.where((id) => !positionsBrutes.containsKey(id)).toList();
    for (var i = 0; i < isoles.length; i++) {
      positionsBrutes[isoles[i]] = Offset(
          (i % parLigneIsoles) * (w + ecartFrere * 2),
          basY + ecartCartes / 2 + (i ~/ parLigneIsoles) * (h + ecartFrere));
    }

    // Coordonnées positives avec marge.
    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
    var premier = true;
    for (final p in positionsBrutes.values) {
      if (premier) {
        minX = maxX = p.dx;
        minY = maxY = p.dy;
        premier = false;
      }
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final decal = Offset(marge - minX, marge - minY);
    positionsBrutes.forEach(
        (id, p) => positions[id] = (x: p.dx + decal.dx, y: p.dy + decal.dy));
    largeur = maxX - minX + w + 2 * marge;
    hauteur = maxY - minY + h + 2 * marge;
    final c =
        (centreBrut ?? Offset(largeur / 2 - decal.dx, hauteur / 2 - decal.dy)) +
            decal;
    centre = (x: c.dx, y: c.dy);

    // Tracés des liaisons (angles droits) : du nœud parent vers l'enfant, selon l'orientation de l'enfant.
    for (final l in g.liens) {
      final a = positions[l.de], b = positions[l.vers];
      if (a == null || b == null) continue;
      final ra = Rect.fromLTWH(a.x, a.y, w, h),
          rb = Rect.fromLTWH(b.x, b.y, w, h);
      final dir = orientations[l.vers] ??
          Offset((rb.center.dx >= ra.center.dx) ? 1 : -1, 0);
      final racine = racines.contains(l.de);
      final List<Offset> pts;
      if (dir.dx != 0) {
        // départ par le côté (étalé sur la hauteur du centre pour la racine), coude à mi-chemin
        final yA = racine
            ? (rb.center.dy).clamp(ra.top + 14, ra.bottom - 14).toDouble()
            : ra.center.dy;
        final xA = dir.dx > 0 ? ra.right : ra.left;
        final xB = dir.dx > 0 ? rb.left : rb.right;
        final xm = (xA + xB) / 2;
        pts = [
          Offset(xA, yA),
          Offset(xm, yA),
          Offset(xm, rb.center.dy),
          Offset(xB, rb.center.dy)
        ];
      } else {
        final xA = racine
            ? (rb.center.dx).clamp(ra.left + 24, ra.right - 24).toDouble()
            : ra.center.dx;
        final yA = dir.dy > 0 ? ra.bottom : ra.top;
        final yB = dir.dy > 0 ? rb.top : rb.bottom;
        final ym = (yA + yB) / 2;
        pts = [
          Offset(xA, yA),
          Offset(xA, ym),
          Offset(rb.center.dx, ym),
          Offset(rb.center.dx, yB)
        ];
      }
      traces['${l.de}>${l.vers}'] = pts;
    }
  }

  final Map<String, Offset> positionsBrutes = {};
  Offset? centreBrut;
  final Map<String, ({double x, double y})> positions = {};

  /// Points des liaisons, par « parent>enfant » (polyligne à angles droits, arrondie au dessin).
  final Map<String, List<Offset>> traces = {};
  late final double largeur;
  late final double hauteur;

  /// Centre du nœud orchestrateur (pour cadrer la vue sur lui).
  late final ({double x, double y}) centre;
}
