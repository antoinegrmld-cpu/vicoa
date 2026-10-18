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
import 'dart:ui' show Offset, Rect;

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

/// Disposition en MINDMAP « tout autour », SANS CROISEMENT : l'orchestrateur au centre, ses lanes réparties sur
/// quatre côtés (haut, droite, bas, gauche). Sur chaque côté, les lanes s'alignent le long d'un TRONC commun qui
/// part de l'orchestrateur : colonne à droite et à gauche, rangée en haut et en bas. Les sous-lanes partent vers
/// l'extérieur de leur lane (colonne sur les côtés, rangée en haut/bas), reliées en accolade. Comme chaque côté
/// occupe sa propre zone et que ses liaisons suivent son tronc, les lignes ne se croisent pas.
class DispositionGraphe {
  static const double largeurNoeud = 230;
  static const double hauteurNoeud = 80;
  static const double ecartTronc =
      60; // orchestrateur -> tronc, et tronc -> lanes
  static const double ecartGroupe = 70; // lane -> ses sous-lanes
  static const double ecartFrere = 24; // entre deux blocs voisins
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
        Offset>{}; // coin haut-gauche, relatif au centre de l'orchestrateur
    final sens = <String,
        Offset>{}; // direction de croissance : (1,0) droite, (-1,0) gauche, (0,-1) haut, (0,1) bas
    var decalageX = 0.0;

    List<String> enfantsLibres(String id) => (enfants[id] ?? const <String>[])
        .where((x) => !places.contains(x))
        .toList();

    // Taille d'un bloc (une lane + toutes ses sous-lanes) le long du tronc : hauteur sur un côté, largeur en haut/bas.
    double etendue(String id, bool lateral, Set<String> vus) {
      if (!vus.add(id)) return 0;
      final e = (enfants[id] ?? const <String>[])
          .where((x) => !vus.contains(x))
          .toList();
      final soi = lateral ? h : w;
      if (e.isEmpty) return soi;
      final total = e
              .map((c) => etendue(c, lateral, vus))
              .fold<double>(0, (a, b) => a + b) +
          (e.length - 1) * ecartFrere;
      return math.max(soi, total);
    }

    // Place les sous-lanes d'un nœud, vers l'extérieur, centrées sur lui.
    void placerEnfants(String parent, Offset dir) {
      final e = enfantsLibres(parent);
      if (e.isEmpty) return;
      places.addAll(e);
      final lateral = dir.dx != 0;
      final tailles = [
        for (final c in e) etendue(c, lateral, {...places}..remove(c))
      ];
      final total = tailles.fold<double>(0, (a, b) => a + b) +
          (e.length - 1) * ecartFrere;
      final p = rel[parent]!;
      var curseur =
          lateral ? p.dy + h / 2 - total / 2 : p.dx + w / 2 - total / 2;
      for (var i = 0; i < e.length; i++) {
        final Offset coin = lateral
            ? Offset(p.dx + dir.dx * (w + ecartGroupe),
                curseur + tailles[i] / 2 - h / 2)
            : Offset(curseur + tailles[i] / 2 - w / 2,
                p.dy + dir.dy * (h + ecartGroupe));
        rel[e[i]] = coin;
        sens[e[i]] = dir;
        curseur += tailles[i] + ecartFrere;
        placerEnfants(e[i], dir);
      }
    }

    for (final r in racines) {
      if (places.contains(r)) continue;
      places.add(r);
      rel
        ..clear()
        ..[r] = const Offset(-w / 2, -h / 2);
      final branches = enfantsLibres(r);
      places.addAll(branches);
      final n = branches.length;

      // Répartition sur les 4 côtés : droite et gauche prennent le plus (une colonne s'allonge mieux),
      // haut et bas quelques-unes ; ordre des aiguilles d'une montre en partant du haut.
      final nHaut = n <= 2 ? 0 : math.max(1, n ~/ 6);
      final nBas = n <= 3 ? 0 : math.max(1, n ~/ 5);
      final reste = n - nHaut - nBas;
      final nDroite = (reste + 1) ~/ 2;
      final haut = branches.sublist(0, nHaut);
      final droite = branches.sublist(nHaut, nHaut + nDroite);
      final bas = branches.sublist(nHaut + nDroite, nHaut + nDroite + nBas);
      final gauche = branches.sublist(nHaut + nDroite + nBas);

      double longueur(List<String> l, bool lateral) => l.isEmpty
          ? 0
          : l
                  .map((b) => etendue(b, lateral, {...places}..remove(b)))
                  .fold<double>(0, (a, b) => a + b) +
              (l.length - 1) * ecartFrere;
      // Profondeur d'un côté (vers l'extérieur) : pour savoir jusqu'où il s'étend.
      double profondeur(String id, bool lateral, Set<String> vus) {
        if (!vus.add(id)) return 0;
        final e = (enfants[id] ?? const <String>[])
            .where((x) => !vus.contains(x))
            .toList();
        final soi = lateral ? w : h;
        if (e.isEmpty) return soi;
        return soi +
            ecartGroupe +
            e.map((c) => profondeur(c, lateral, vus)).fold<double>(0, math.max);
      }

      final hDroite = longueur(droite, true), hGauche = longueur(gauche, true);
      final lHaut = longueur(haut, false), lBas = longueur(bas, false);

      // Colonnes latérales : tronc vertical à ecartTronc de l'orchestrateur, lanes un cran plus loin.
      void colonne(List<String> l, int cote) {
        var y = -longueur(l, true) / 2;
        for (final b in l) {
          final t = etendue(b, true, {...places}..remove(b));
          final x =
              cote > 0 ? w / 2 + 2 * ecartTronc : -w / 2 - 2 * ecartTronc - w;
          rel[b] = Offset(x, y + t / 2 - h / 2);
          sens[b] = Offset(cote.toDouble(), 0);
          placerEnfants(b, Offset(cote.toDouble(), 0));
          y += t + ecartFrere;
        }
      }

      colonne(droite, 1);
      colonne(gauche, -1);

      // Rangées du haut et du bas : placées au-delà des colonnes si elles débordent sur leur largeur,
      // pour ne jamais passer par-dessus les lanes de côté.
      const largeurColonnes = w / 2 + 2 * ecartTronc;
      void rangee(List<String> l, int cote) {
        if (l.isEmpty) return;
        final largeurRangee = longueur(l, false);
        final colonnes = cote < 0
            ? math.max(hDroite, hGauche) / 2
            : math.max(hDroite, hGauche) / 2;
        final deborde = largeurRangee / 2 > largeurColonnes;
        final distance = math.max(
            h / 2 + 2 * ecartTronc, deborde ? colonnes + ecartTronc * 2 : 0.0);
        var x = -largeurRangee / 2;
        for (final b in l) {
          final t = etendue(b, false, {...places}..remove(b));
          final y = cote > 0 ? distance : -distance - h;
          rel[b] = Offset(x + t / 2 - w / 2, y);
          sens[b] = Offset(0, cote.toDouble());
          placerEnfants(b, Offset(0, cote.toDouble()));
          x += t + ecartFrere;
        }
      }

      rangee(haut, -1);
      rangee(bas, 1);
      // (profondeur et lHaut/lBas servent au calcul ci-dessus ; gardés pour lisibilité)
      assert(lHaut >= 0 && lBas >= 0 && profondeur(r, true, {}) >= 0);

      // Cette mindmap est placée à droite des précédentes.
      var minX = double.infinity, maxX = -double.infinity;
      for (final p in rel.values) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx + w);
      }
      rel.forEach(
          (k, p) => positionsBrutes[k] = p + Offset(decalageX - minX, 0));
      decalageX += maxX - minX + ecartCartes;
      centreBrut ??= positionsBrutes[r]! + const Offset(w / 2, h / 2);
      // Côté de chaque lane de premier niveau (pour tracer le tronc).
      for (final b in droite) {
        cotes[b] = 'droite';
      }
      for (final b in gauche) {
        cotes[b] = 'gauche';
      }
      for (final b in haut) {
        cotes[b] = 'haut';
      }
      for (final b in bas) {
        cotes[b] = 'bas';
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

    // Tracés à angles droits : orchestrateur -> tronc -> lane ; lane -> accolade -> sous-lanes.
    for (final l in g.liens) {
      final a = positions[l.de], b = positions[l.vers];
      if (a == null || b == null) continue;
      final ra = Rect.fromLTWH(a.x, a.y, w, h),
          rb = Rect.fromLTWH(b.x, b.y, w, h);
      final cote = cotes[l.vers];
      final dir =
          sens[l.vers] ?? Offset(rb.center.dx >= ra.center.dx ? 1 : -1, 0);
      final List<Offset> pts;
      if (cote == 'droite' || cote == 'gauche') {
        // tronc vertical à ecartTronc du bord de l'orchestrateur : tous les liens de ce côté le partagent
        final xA = cote == 'droite' ? ra.right : ra.left;
        final xT =
            cote == 'droite' ? ra.right + ecartTronc : ra.left - ecartTronc;
        final xB = cote == 'droite' ? rb.left : rb.right;
        pts = [
          Offset(xA, ra.center.dy),
          Offset(xT, ra.center.dy),
          Offset(xT, rb.center.dy),
          Offset(xB, rb.center.dy)
        ];
      } else if (cote == 'haut' || cote == 'bas') {
        // tronc horizontal juste au-dessus (ou au-dessous) des lanes du côté, rejoint par le milieu de l'orchestrateur
        final yA = cote == 'haut' ? ra.top : ra.bottom;
        final yB = cote == 'haut' ? rb.bottom : rb.top;
        final yT = cote == 'haut' ? yB + ecartTronc : yB - ecartTronc;
        pts = [
          Offset(ra.center.dx, yA),
          Offset(ra.center.dx, yT),
          Offset(rb.center.dx, yT),
          Offset(rb.center.dx, yB)
        ];
      } else if (dir.dx != 0) {
        // accolade latérale vers les sous-lanes
        final xA = dir.dx > 0 ? ra.right : ra.left,
            xB = dir.dx > 0 ? rb.left : rb.right;
        final xm = (xA + xB) / 2;
        pts = [
          Offset(xA, ra.center.dy),
          Offset(xm, ra.center.dy),
          Offset(xm, rb.center.dy),
          Offset(xB, rb.center.dy)
        ];
      } else {
        // accolade verticale vers les sous-lanes
        final yA = dir.dy > 0 ? ra.bottom : ra.top,
            yB = dir.dy > 0 ? rb.top : rb.bottom;
        final ym = (yA + yB) / 2;
        pts = [
          Offset(ra.center.dx, yA),
          Offset(ra.center.dx, ym),
          Offset(rb.center.dx, ym),
          Offset(rb.center.dx, yB)
        ];
      }
      traces['${l.de}>${l.vers}'] = pts;
    }
  }

  final Map<String, Offset> positionsBrutes = {};
  final Map<String, String> cotes = {};
  Offset? centreBrut;
  final Map<String, ({double x, double y})> positions = {};

  /// Points des liaisons, par « parent>enfant » (polyligne à angles droits, arrondie au dessin).
  final Map<String, List<Offset>> traces = {};
  late final double largeur;
  late final double hauteur;

  /// Centre du nœud orchestrateur (pour cadrer la vue sur lui).
  late final ({double x, double y}) centre;
}
