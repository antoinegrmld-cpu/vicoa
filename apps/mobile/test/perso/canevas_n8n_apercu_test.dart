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

    tester.view.physicalSize = const Size(4000, 3000);
    tester.view.devicePixelRatio = 2;
    final sessions = [
      _s('o', 'ORCH diag-auto', 'OpenCode', 'abliterated-model-large-v2', 'ACTIVE'),
      _s('p', 'Lane POURQUOI : objectifs', 'OpenCode', 'abliterated-model-large-v2', 'ACTIVE'),
      _s('p1', 'Motivations', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('p2', 'Causes', 'Claude Code', 'claude-haiku-5-5', 'ACTIVE'),
      _s('p3', 'Objectifs', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('c', 'Lane COMMENT : méthode', 'Claude Code', 'claude-sonnet-5-5', 'AWAITING_INPUT'),
      _s('c1', 'Conditions', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('c2', 'Procédures', 'OpenCode', 'abliterated-model-large-v2', 'AWAITING_INPUT'),
      _s('c3', 'Moyens', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('c4', 'Circonstances', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('qui', 'Lane QUI : acteurs', 'Claude Code', 'claude-opus-5-5', 'COMPLETED'),
      _s('qd', 'Lane QUAND : planning', 'OpenCode', 'abliterated-model-large-v2', 'ACTIVE'),
      _s('qd1', 'Période', 'Claude Code', 'claude-haiku-5-5', 'ACTIVE'),
      _s('qd2', 'Date', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('qd3', 'Durée', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('cb', 'Lane COMBIEN : budget', 'Claude Code', 'claude-sonnet-5-5', 'COMPLETED'),
      _s('cb1', 'Mesures', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('cb2', 'Coût', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('cb3', 'Quantité', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('ou', 'Lane OÙ : lieux', 'OpenCode', 'abliterated-model-large-v2', 'COMPLETED'),
      _s('ou1', 'Destination', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('ou2', 'Lieu', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('ou3', 'Origine', 'Claude Code', 'claude-haiku-5-5', 'COMPLETED'),
      _s('quoi', 'Lane QUOI : périmètre', 'Claude Code', 'claude-sonnet-5-5', 'ACTIVE'),
    ];
    final graphe = GrapheProjet(sessions, const [
      LienAgent('o', 'p'), LienAgent('o', 'c'), LienAgent('o', 'qui'), LienAgent('o', 'qd'),
      LienAgent('o', 'cb'), LienAgent('o', 'ou'), LienAgent('o', 'quoi'),
      LienAgent('p', 'p1'), LienAgent('p', 'p2'), LienAgent('p', 'p3'),
      LienAgent('c', 'c1'), LienAgent('c', 'c2'), LienAgent('c', 'c3'), LienAgent('c', 'c4'),
      LienAgent('qd', 'qd1'), LienAgent('qd', 'qd2'), LienAgent('qd', 'qd3'),
      LienAgent('cb', 'cb1'), LienAgent('cb', 'cb2'), LienAgent('cb', 'cb3'),
      LienAgent('ou', 'ou1'), LienAgent('ou', 'ou2'), LienAgent('ou', 'ou3'),
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
