// Vicoa Perso — panneau de détail d'un agent : tâche en cours, derniers messages,
// outils utilisés, et envoi d'une instruction (même fonction que l'écran de chat d'origine).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/custom_code/actions/index.dart' as actions;
import '/custom_code/widgets/tool_use_group.dart'
    show isToolUseContent, summarizeToolMessage;
import '/index.dart' show AgentChatWidget;
import 'canevas_n8n.dart' show apparenceAgent;
import 'perso_commun.dart' show ilYA, libelleStatut;
import 'perso_store.dart';
import 'perso_theme.dart';

Future<void> ouvrirDetailAgent(
    BuildContext context, Map<String, dynamic> session) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PaletteN8n.carte,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, defilement) => Theme(
        data: themeN8n(context),
        child: _DetailAgent(
            sessionId: session['id'].toString(), defilement: defilement),
      ),
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

  Map<String, dynamic> get session =>
      store.sessions.firstWhere((s) => s['id'].toString() == widget.sessionId,
          orElse: () => {'id': widget.sessionId});

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
      messages = liste
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final taskId = session['task_id']?.toString();
      if (taskId != null && taskId.isNotEmpty) {
        final taches = await actions.apiGetTasks();
        final t =
            taches.whereType<Map>().where((x) => x['id']?.toString() == taskId);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Envoi impossible. L'agent est-il joignable ?")));
      return;
    }
    saisie.clear();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Instruction envoyée.')));
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final statut = statutDe(s);
    final a = apparenceAgent(s);
    final textes = messages
        .where((m) => !isToolUseContent((m['content'] ?? '').toString()))
        .toList();
    final outils = messages
        .where((m) => isToolUseContent((m['content'] ?? '').toString()))
        .map((m) => summarizeToolMessage((m['content'] ?? '').toString()))
        .toList();
    final derniers =
        textes.length > 8 ? textes.sublist(textes.length - 8) : textes;
    final derniersOutils =
        outils.length > 10 ? outils.sublist(outils.length - 10) : outils;

    return Column(children: [
      Expanded(
        child: ListView(
          controller: widget.defilement,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: PaletteN8n.lien,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              BlocIcone(icone: a.icone, couleur: a.couleur, taille: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nomDe(s),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TexteN8n.sousTitre),
                      const SizedBox(height: 3),
                      Text('${a.court} · ${modeleDe(s)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TexteN8n.doux),
                    ]),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: couleurStatutN8n(statut).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: couleurStatutN8n(statut).withValues(alpha: 0.5)),
                ),
                child: Text(libelleStatut(statut),
                    style: TexteN8n.doux.copyWith(
                        color: couleurStatutN8n(statut),
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(ilYA(dateDe(s)), style: TexteN8n.doux),
            ]),
            const SizedBox(height: 14),
            _Section(
                titre: 'Tâche en cours',
                enfant: Text(
                    tache ??
                        (s['latest_message'] ?? 'Pas de tâche liée.')
                            .toString(),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TexteN8n.corps)),
            _Section(
              titre: 'Derniers messages',
              enfant: chargement
                  ? const LinearProgressIndicator()
                  : derniers.isEmpty
                      ? const Text('Aucun message.', style: TexteN8n.doux)
                      : Column(children: [
                          for (final m in derniers) _Bulle(message: m),
                        ]),
            ),
            _Section(
              titre: 'Outils utilisés',
              enfant: derniersOutils.isEmpty
                  ? const Text('Aucun outil pour le moment.',
                      style: TexteN8n.doux)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final o in derniersOutils.reversed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin:
                                        const EdgeInsets.only(right: 8, top: 1),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: PaletteN8n.accent
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(o.name,
                                        style: const TextStyle(
                                            color: PaletteN8n.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Expanded(
                                    child: Text(o.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TexteN8n.doux),
                                  ),
                                ]),
                          ),
                      ],
                    ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: PaletteN8n.accent),
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
          padding: EdgeInsets.fromLTRB(
              12, 6, 12, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: saisie,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _envoyer(),
                style: TexteN8n.corps,
                decoration:
                    const InputDecoration(hintText: 'Donner une instruction…'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: PaletteN8n.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: envoi ? null : _envoyer,
              icon: envoi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PaletteN8n.champ,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PaletteN8n.bord),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre.toUpperCase(), style: TexteN8n.etiquette),
        const SizedBox(height: 8),
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
    final deMoi =
        (message['sender_type'] ?? '').toString().toLowerCase() == 'user';
    return Align(
      alignment: deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: deMoi
              ? PaletteN8n.accent.withValues(alpha: 0.18)
              : PaletteN8n.carteHaut,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(deMoi ? 12 : 3),
            bottomRight: Radius.circular(deMoi ? 3 : 12),
          ),
          border: Border.all(
              color: deMoi
                  ? PaletteN8n.accent.withValues(alpha: 0.4)
                  : PaletteN8n.bord),
        ),
        child: Text((message['content'] ?? '').toString(),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TexteN8n.corps.copyWith(fontSize: 13.5)),
      ),
    );
  }
}
