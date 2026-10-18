// Vicoa Perso — données partagées des nouveaux écrans (accueil en projets, graphe, détail).
//
// Réutilise uniquement ce que l'appli d'origine fournit déjà :
//   - REST : apiGetProjects, apiGetAllAgentInstances, apiGetMachines ;
//   - temps réel : VicoaWsClient (instanceEvents + messageArrivedEvents) ;
//   - regroupement par projet : sessionProjectKey (pages/home/project_groups.dart).
// Aucun appel nouveau côté serveur.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '/custom_code/actions/index.dart' as actions;
import '/custom_code/utils/machine_utils.dart' as mutils;
import '/pages/home/project_groups.dart' show sessionProjectKey;

/// Statuts qui veulent dire « l'agent tourne ou attend quelque chose ».
const Set<String> kStatutsActifs = {
  'STARTING',
  'ACTIVE',
  'AWAITING_INPUT',
  'PAUSED',
};

/// Un projet tel qu'affiché par Vicoa Perso : le projet Vicoa (s'il existe)
/// et les sessions qui lui appartiennent.
class ProjetPerso {
  ProjetPerso({required this.cle, required this.nom, this.projet});

  final String cle; // project_id, sinon nom du dossier (même règle que l'accueil d'origine)
  final String nom;
  final Map<String, dynamic>? projet;
  final List<Map<String, dynamic>> sessions = [];

  int get agentsActifs =>
      sessions.where((s) => kStatutsActifs.contains(statutDe(s))).length;

  DateTime? get derniereActivite {
    DateTime? max;
    for (final s in sessions) {
      final d = dateDe(s);
      if (d != null && (max == null || d.isAfter(max))) max = d;
    }
    final p = DateTime.tryParse(projet?['last_activity_at']?.toString() ?? '');
    if (p != null && (max == null || p.isAfter(max))) max = p;
    return max;
  }

  /// Dossier de travail du projet (sert à lire hub.json sur le PC).
  String? get dossier {
    final dirs = projet?['directories'];
    if (dirs is List && dirs.isNotEmpty && dirs.first is Map) {
      final p = (dirs.first as Map)['local_path']?.toString();
      if (p != null && p.isNotEmpty) return p;
    }
    for (final s in sessions) {
      final p = s['project']?.toString();
      if (p != null && p.isNotEmpty) return p;
    }
    return null;
  }

  String? get machineId {
    final dirs = projet?['directories'];
    if (dirs is List && dirs.isNotEmpty && dirs.first is Map) {
      final m = (dirs.first as Map)['machine_id']?.toString();
      if (m != null && m.isNotEmpty) return m;
    }
    for (final s in sessions) {
      final m = s['machine_id']?.toString();
      if (m != null && m.isNotEmpty) return m;
    }
    return null;
  }
}

String statutDe(Map s) => (s['status'] ?? '').toString().toUpperCase();

DateTime? dateDe(Map s) => DateTime.tryParse(
    (s['latest_message_at'] ?? s['last_heartbeat_at'] ?? s['started_at'] ?? '')
        .toString());

String nomDe(Map s) {
  final n = (s['name'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  final t = (s['agent_type_name'] ?? 'Agent').toString();
  return '$t ${s['id'].toString().substring(0, 6)}';
}

String modeleDe(Map s) {
  final cfg = s['session_config'];
  if (cfg is Map && (cfg['model'] ?? '').toString().isNotEmpty) {
    return cfg['model'].toString();
  }
  return (s['agent_type_name'] ?? '').toString();
}

/// Magasin unique, partagé par tous les écrans Perso (comme FFAppState).
class PersoStore extends ChangeNotifier {
  PersoStore._();
  static final PersoStore instance = PersoStore._();

  List<Map<String, dynamic>> projets = [];
  List<Map<String, dynamic>> sessions = [];
  List<dynamic> machines = [];
  bool chargement = false;
  String? erreur;
  DateTime? misAJour;

  StreamSubscription? _subInstances;
  StreamSubscription? _subMessages;
  int _abonnes = 0;
  Timer? _rafraichissement;

  /// Un écran qui affiche les données appelle [ouvrir] dans initState et
  /// [fermer] dans dispose : le temps réel reste ouvert tant qu'un écran l'utilise.
  void ouvrir() {
    _abonnes += 1;
    if (_abonnes == 1) {
      final ws = actions.VicoaWsClient.instance;
      ws.retain();
      _subInstances = ws.instanceEvents.listen(_surEvenementInstance);
      _subMessages = ws.messageArrivedEvents.listen(_surMessage);
      // Filet de sécurité : relecture complète toutes les 2 minutes.
      _rafraichissement =
          Timer.periodic(const Duration(minutes: 2), (_) => charger());
    }
    if (misAJour == null ||
        DateTime.now().difference(misAJour!) > const Duration(seconds: 30)) {
      charger();
    }
  }

  void fermer() {
    if (_abonnes == 0) return;
    _abonnes -= 1;
    if (_abonnes == 0) {
      _subInstances?.cancel();
      _subMessages?.cancel();
      _rafraichissement?.cancel();
      actions.VicoaWsClient.instance.release();
    }
  }

  Future<void> charger() async {
    if (chargement) return;
    chargement = true;
    erreur = null;
    notifyListeners();
    try {
      final resultats = await Future.wait([
        actions.apiGetProjects(),
        _toutesLesSessions(),
        actions.apiGetMachines(),
      ]);
      projets = resultats[0]
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .where((p) => p['is_archived'] != true)
          .toList();
      sessions = resultats[1] as List<Map<String, dynamic>>;
      machines = resultats[2];
      misAJour = DateTime.now();
    } catch (e) {
      erreur = e.toString();
    } finally {
      chargement = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> _toutesLesSessions() async {
    final res = <Map<String, dynamic>>[];
    for (var page = 1; page <= 4; page++) {
      final r = await actions.apiGetAllAgentInstances(page: page, pageSize: 50);
      res.addAll((r['items'] as List)
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s)));
      if (r['hasMore'] != true) break;
    }
    return res.where((s) => statutDe(s) != 'DELETED').toList();
  }

  void _surEvenementInstance(Map<String, dynamic> e) {
    final data = e['data'];
    if (e['event'] == 'connected') {
      charger();
      return;
    }
    if (data is! Map) return;
    final id = data['id']?.toString();
    if (id == null) return;
    final i = sessions.indexWhere((s) => s['id']?.toString() == id);
    final fusion = {
      if (i >= 0) ...sessions[i],
      ...Map<String, dynamic>.from(data),
    };
    if (i >= 0) {
      sessions[i] = fusion;
    } else {
      sessions.insert(0, fusion);
    }
    notifyListeners();
  }

  void _surMessage(Map<String, dynamic> e) {
    final id = e['instance_id']?.toString();
    final data = e['data'];
    final i = sessions.indexWhere((s) => s['id']?.toString() == id);
    if (i < 0 || data is! Map) return;
    sessions[i] = {
      ...sessions[i],
      'latest_message': data['content'] ?? sessions[i]['latest_message'],
      'latest_message_at': data['created_at'] ?? DateTime.now().toIso8601String(),
    };
    notifyListeners();
  }

  /// Projets (avec leurs sessions), du plus récemment actif au moins actif,
  /// et les conversations hors projet.
  ({List<ProjetPerso> projets, List<Map<String, dynamic>> horsProjet})
      regrouper() {
    final parId = {for (final p in projets) p['id'].toString(): p};
    final groupes = <String, ProjetPerso>{};
    final horsProjet = <Map<String, dynamic>>[];
    for (final s in sessions) {
      final cle = sessionProjectKey(s);
      if (cle == '__no_project__') {
        horsProjet.add(s);
        continue;
      }
      final projet = parId[cle];
      groupes
          .putIfAbsent(
              cle,
              () => ProjetPerso(
                  cle: cle,
                  nom: (projet?['name'] ?? cle).toString(),
                  projet: projet))
          .sessions
          .add(s);
    }
    // Projets Vicoa encore vides : on les montre aussi (ex. créés à l'import).
    for (final p in projets) {
      final cle = p['id'].toString();
      groupes.putIfAbsent(
          cle, () => ProjetPerso(cle: cle, nom: p['name'].toString(), projet: p));
    }
    final liste = groupes.values.toList()
      ..sort((a, b) {
        final da = a.derniereActivite, db = b.derniereActivite;
        if (da == null && db == null) return a.nom.compareTo(b.nom);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    horsProjet.sort((a, b) =>
        (dateDe(b) ?? DateTime(2000)).compareTo(dateDe(a) ?? DateTime(2000)));
    return (projets: liste, horsProjet: horsProjet);
  }

  ProjetPerso? projetParCle(String cle) {
    for (final p in regrouper().projets) {
      if (p.cle == cle) return p;
    }
    return null;
  }

  /// Machine allumée (pour parler au PC : hub.json, import).
  String? machineEnLigne() {
    for (final m in mutils.sortMachinesByStatus(machines)) {
      if (mutils.isMachineOnlineFromMap(m)) return mutils.machineId(m);
    }
    return machines.isNotEmpty ? mutils.machineId(machines.first) : null;
  }
}
