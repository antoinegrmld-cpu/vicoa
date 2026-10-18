// Aperçu visuel du canevas « façon n8n » (Vicoa Perso) avec des agents fictifs.
// Écrit test/perso/apercu_canevas_hd.png (haute définition) :  flutter test test/perso

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

Future<void> _police(String famille, String fichier) async {
  final f = File(fichier);
  if (!f.existsSync()) return;
  final loader = FontLoader(famille)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('aperçu HD du canevas n8n', (tester) async {
    // Polices réelles (les tests Flutter dessinent sinon des carrés).
    await _police('Roboto', r'C:\Windows\Fonts\segoeui.ttf');
    await _police('MaterialIcons',
        r'C:\hub-agents\outils-dev\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf');

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
    final cle = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        body: RepaintBoundary(
          key: cle,
          child: CanevasAgents(graphe: graphe, session: (id) => sessions.firstWhere((s) => s['id'] == id)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.runAsync(() async {
      final rendu = cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await rendu.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('test/perso/apercu_canevas_hd.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
