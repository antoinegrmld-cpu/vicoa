// Aperçu visuel du canevas « façon n8n » (Vicoa Perso) avec des agents fictifs.
// Génère test/perso/apercu_canevas.png :  flutter test test/perso --update-goldens

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:vicoa/perso/canevas_n8n.dart';
import 'package:vicoa/perso/perso_hub.dart';

Map<String, dynamic> _s(String id, String nom, String agent, String modele, String statut) => {
      'id': id,
      'name': nom,
      'agent_type_name': agent,
      'session_config': {'model': modele},
      'status': statut,
    };

Future<void> _chargerPolices() async {
  // Police réelle de Windows pour que l'aperçu soit lisible (les tests utilisent sinon des carrés).
  final f = File(r'C:\Windows\Fonts\segoeui.ttf');
  final g = File(r'C:\Windows\Fonts\seguisb.ttf');
  if (f.existsSync()) {
    for (final famille in ['Roboto', 'SourceSans3_regular', 'SourceSans3_400', 'SourceSans3_500', 'SourceSans3_600', 'SourceSans3_700']) {
      final fichier = famille.endsWith('600') || famille.endsWith('700') || famille.endsWith('500') ? (g.existsSync() ? g : f) : f;
      final loader = FontLoader(famille)..addFont(Future.value(ByteData.sublistView(fichier.readAsBytesSync())));
      await loader.load();
    }
  }
  final icones = File(r'C:\hub-agents\outils-dev\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf');
  if (icones.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icones.readAsBytesSync())));
    await loader.load();
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  testWidgets('aperçu du canevas n8n', (tester) async {
    await _chargerPolices();
    tester.view.physicalSize = const Size(1080, 1500);
    tester.view.devicePixelRatio = 2.5;
    final sessions = [
      _s('o', 'ORCH diag-auto', 'OpenCode', 'abliterated-model-large-v2', 'ACTIVE'),
      _s('a', 'Lane FIAB : étiquetage', 'Claude Code', 'claude-opus-5-5', 'ACTIVE'),
      _s('b', 'Lane TRAD : codes défaut FR', 'Claude Code', 'claude-sonnet-5-5', 'AWAITING_INPUT'),
      _s('c', 'Lane DOC : documentation', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('d', 'Repérage données Diagbox', 'OpenCode', 'abliterated-model-large-v2', 'PAUSED'),
    ];
    final graphe = GrapheProjet(sessions, const [
      LienAgent('o', 'a'),
      LienAgent('o', 'b'),
      LienAgent('o', 'c'),
    ], 'hub.json');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.light),
      home: Scaffold(
        body: CanevasAgents(graphe: graphe, session: (id) => sessions.firstWhere((s) => s['id'] == id)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(CanevasAgents), matchesGoldenFile('apercu_canevas.png'));
  });
}
