// Vicoa Perso — dialogue avec le service du PC (C:\hub-agents\vicoa-import\service_import.py) par fichiers,
// via le démon Vicoa (RPC read-file / write-file) : contenu d'une lane du PC, envoi d'un message à une session
// OpenCode « tout de suite » (steer) ou en file d'attente.

import 'dart:async';
import 'dart:convert';

import '/custom_code/actions/index.dart' as actions;
import 'perso_hub.dart' show ecrireFichierPc, kDossierImportPc, lireFichierPc;
import 'perso_store.dart';

/// Écrit une demande pour le service du PC et attend sa réponse (relue toutes les 1,5 s).
/// Renvoie la demande complétée par le PC ; lève une exception si le PC ne répond pas.
Future<Map<String, dynamic>> demanderAuPc(Map<String, dynamic> demande,
    {Set<String> etatsFinaux = const {},
    Duration delai = const Duration(seconds: 40)}) async {
  final machine = PersoStore.instance.machineEnLigne();
  if (machine == null) {
    throw Exception('Aucun PC relié à Vicoa (vicoa daemon arrêté ?).');
  }
  final id = 'rapide-${DateTime.now().millisecondsSinceEpoch}';
  final err = await ecrireFichierPc(
      machine, kDossierImportPc, 'demandes/$id.json', jsonEncode(demande));
  if (err != null) throw Exception('Écriture impossible sur le PC : $err');
  final fin = DateTime.now().add(delai);
  while (DateTime.now().isBefore(fin)) {
    await Future.delayed(const Duration(milliseconds: 1500));
    final texte =
        await lireFichierPc(machine, kDossierImportPc, 'demandes/$id.json');
    if (texte == null) continue;
    final d = Map<String, dynamic>.from(jsonDecode(texte) as Map);
    if (d['etat'] == 'erreur_rapide') {
      throw Exception(d['erreur'] ?? 'erreur sur le PC');
    }
    if (etatsFinaux.contains(d['etat'])) return d;
  }
  throw Exception("Le PC ne répond pas (service d'import arrêté ?).");
}

/// Derniers messages d'une session du PC (OpenCode ou Claude Code), du plus ancien au plus récent.
Future<List<Map<String, dynamic>>> contenuSessionPc(String agent, String id,
    {int n = 40}) async {
  final d = await demanderAuPc(
      {'etat': 'contenu', 'agent': agent, 'id': id, 'n': n},
      etatsFinaux: {'contenu_pret'});
  return (d['messages'] as List? ?? const [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

/// Envoie un message à une session OpenCode du PC : tout de suite (dans le tour en cours) ou après son tour.
Future<void> envoyerSessionOpenCode(
    {String? sessionOpenCode,
    String? vicoaId,
    required String texte,
    bool toutDeSuite = true}) {
  return demanderAuPc({
    'etat': 'envoyer',
    'agent': 'opencode',
    if (sessionOpenCode != null) 'id': sessionOpenCode,
    if (vicoaId != null) 'vicoa_id': vicoaId,
    'texte': texte,
    'livraison': toutDeSuite ? 'steer' : 'file',
  }, etatsFinaux: {
    'envoye'
  });
}

/// « Envoyer tout de suite » pour un message en file d'attente d'une session OpenCode de Vicoa
/// (Vicoa ne sait pas le faire pour OpenCode) : on retire le message de la file Vicoa, puis le PC le remet
/// directement à OpenCode, qui le prend en compte pendant son tour. Renvoie false si le message n'était plus en file.
Future<bool> envoyerToutDeSuiteOpenCodeVicoa(
    String instanceId, String messageId, String texte) async {
  final retire = await actions.apiCancelQueuedMessage(instanceId, messageId);
  if (!retire) return false;
  await envoyerSessionOpenCode(
      vicoaId: instanceId, texte: texte, toutDeSuite: true);
  return true;
}
