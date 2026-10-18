// Vicoa Perso — panneau de détail d'un agent : tâche en cours, derniers messages,
// outils utilisés, et envoi d'une instruction (même fonction que l'écran de chat d'origine).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/custom_code/actions/index.dart' as actions;
import '/custom_code/widgets/tool_use_group.dart' show isToolUseContent, summarizeToolMessage;
import '/flutter_flow/flutter_flow_theme.dart';
import '/index.dart' show AgentChatWidget;
import 'perso_commun.dart';
import 'perso_store.dart';

Future<void> ouvrirDetailAgent(BuildContext context, Map<String, dynamic> session) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, defilement) =>
          _DetailAgent(sessionId: session['id'].toString(), defilement: defilement),
    ),
  );
}

class _DetailAgent extends StatefulWidget {
  const _DetailAgent({required this.sessionId, required this.defilement});
  final String sessionId;
  final ScrollController defilement;

  @override
  State<_DetailAgent> createState() => _DetailAgentState();
}

class _DetailAgentState extends State<_DetailAgent> {
  final store = PersoStore.instance;
  final saisie = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  String? tache;
  bool chargement = true, envoi = false;
  StreamSubscription? _sub;

  Map<String, dynamic> get session => store.sessions
      .firstWhere((s) => s['id'].toString() == widget.sessionId, orElse: () => {'id': widget.sessionId});

  @override
  void initState() {
    super.initState();
    store.addListener(_maj);
    final ws = actions.VicoaWsClient.instance;
    ws.retain();
    ws.watchInstance(widget.sessionId);
    _sub = ws.messageEventsFor(widget.sessionId).listen((e) {
      if (e['event'] == 'message' && e['data'] is Map) {
        final m = Map<String, dynamic>.from(e['data'] as Map);
        if (!messages.any((x) => x['id'] == m['id'])) {
          setState(() => messages.add(m));
        }
      }
    });
    _charger();
  }

  @override
  void dispose() {
    store.removeListener(_maj);
    _sub?.cancel();
    final ws = actions.VicoaWsClient.instance;
    ws.unwatchInstance(widget.sessionId);
    ws.release();
    saisie.dispose();
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  Future<void> _charger() async {
    try {
      final liste = await actions.apiGetInstanceMessages(widget.sessionId);
      messages = liste.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      final taskId = session['task_id']?.toString();
      if (taskId != null && taskId.isNotEmpty) {
        final taches = await actions.apiGetTasks();
        final t = taches.whereType<Map>().where((x) => x['id']?.toString() == taskId);
        if (t.isNotEmpty) tache = (t.first['title'] ?? '').toString();
      }
    } catch (_) {
      // on affiche ce qu'on a
    }
    if (mounted) setState(() => chargement = false);
  }

  Future<void> _envoyer() async {
    final texte = saisie.text.trim();
    if (texte.isEmpty || envoi) return;
    setState(() => envoi = true);
    final r = await actions.apiChatWithAgent(widget.sessionId, texte);
    if (!mounted) return;
    setState(() => envoi = false);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Envoi impossible. L'agent est-il joignable ?")));
      return;
    }
    saisie.clear();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Instruction envoyée.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final s = session;
    final statut = statutDe(s);
    final textes = messages.where((m) => !isToolUseContent((m['content'] ?? '').toString())).toList();
    final outils = messages
        .where((m) => isToolUseContent((m['content'] ?? '').toString()))
        .map((m) => summarizeToolMessage((m['content'] ?? '').toString()))
        .toList();
    final derniers = textes.length > 8 ? textes.sublist(textes.length - 8) : textes;
    final derniersOutils = outils.length > 10 ? outils.sublist(outils.length - 10) : outils;

    return Column(children: [
      Expanded(
        child: ListView(
          controller: widget.defilement,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: t.alternate, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Pastille(statut: statut, taille: 12),
              const SizedBox(width: 8),
              Expanded(child: Text(nomDe(s), style: t.titleMedium)),
            ]),
            const SizedBox(height: 4),
            Text('${modeleDe(s)} · ${libelleStatut(statut)} · ${ilYA(dateDe(s))}',
                style: t.labelSmall.copyWith(color: t.secondaryText)),
            const SizedBox(height: 14),
            _Section(titre: 'Tâche en cours', enfant: Text(
              tache ?? (s['latest_message'] ?? 'Pas de tâche liée.').toString(),
              maxLines: 6, overflow: TextOverflow.ellipsis, style: t.bodyMedium)),
            _Section(
              titre: 'Derniers messages',
              enfant: chargement
                  ? const LinearProgressIndicator()
                  : derniers.isEmpty
                      ? Text('Aucun message.', style: t.bodySmall)
                      : Column(children: [
                          for (final m in derniers) _Bulle(message: m),
                        ]),
            ),
            _Section(
              titre: 'Outils utilisés',
              enfant: derniersOutils.isEmpty
                  ? Text('Aucun outil pour le moment.', style: t.bodySmall)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final o in derniersOutils.reversed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text('• ${o.name} — ${o.description}',
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                          ),
                      ],
                    ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Ouvrir la conversation complète'),
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(AgentChatWidget.routeName,
                    pathParameters: {'instanceId': widget.sessionId},
                    extra: <String, dynamic>{'instanceData': s});
              },
            ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: saisie,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _envoyer(),
                decoration: InputDecoration(
                  hintText: 'Donner une instruction…',
                  filled: true,
                  fillColor: t.primaryBackground,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: t.alternate)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: envoi ? null : _envoyer,
              icon: envoi
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.titre, required this.enfant});
  final String titre;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.primaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.alternate),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: t.labelSmall.copyWith(color: t.secondaryText, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        enfant,
      ]),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message});
  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final t = FlutterFlowTheme.of(context);
    final deMoi = (message['sender_type'] ?? '').toString().toLowerCase() == 'user';
    return Align(
      alignment: deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: deMoi ? t.primary.withValues(alpha: 0.15) : t.secondaryBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text((message['content'] ?? '').toString(),
            maxLines: 6, overflow: TextOverflow.ellipsis, style: t.bodySmall),
      ),
    );
  }
}
