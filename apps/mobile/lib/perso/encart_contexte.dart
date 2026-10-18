// Vicoa Perso — encart « Contexte » d'une session OpenCode : combien de place reste-t-il avant la passation ?
// Taille du contexte au dernier tour (lue sur le PC) comparée au seuil de passation (60 000 tokens, règle de
// ~/.config/opencode/AGENTS.md). Vert : on peut redonner du travail ; orange : prévoir la passation ;
// rouge : demander la passation.

import 'dart:async';

import 'package:flutter/material.dart';

import 'perso_pc.dart';

/// Message prêt à envoyer pour demander la passation (règle « une seule session par rôle »).
const kMessagePassation =
    'Fais ta passation maintenant : mets à jour ton fichier de passation, puis compresse cette session '
    'SUR PLACE (compacter_session.py --ici --reprendre), comme le prévoit AGENTS.md. Ne crée pas de nouvelle session.';

class EncartContexte extends StatefulWidget {
  const EncartContexte({
    super.key,
    this.sessionOpenCode,
    this.vicoaId,
    this.onPassation,
    this.replie = false,
  });

  /// Session OpenCode du PC (ses_…) ou, à défaut, session Vicoa qui l'enveloppe.
  final String? sessionOpenCode;
  final String? vicoaId;

  /// Si fourni : bouton « Demander la passation » (reçoit le message à envoyer).
  final void Function(String message)? onPassation;

  /// Version une ligne (haut du chat) ; un appui déplie le détail.
  final bool replie;

  @override
  State<EncartContexte> createState() => _EncartContexteState();
}

class _EncartContexteState extends State<EncartContexte> {
  Map<String, dynamic>? mesure;
  String? erreur;
  bool deplie = false;
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    deplie = !widget.replie;
    _mesurer();
    _minuterie = Timer.periodic(const Duration(seconds: 30), (_) => _mesurer());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _mesurer() async {
    try {
      final m = await contexteSessionOpenCode(
          sessionOpenCode: widget.sessionOpenCode, vicoaId: widget.vicoaId);
      if (mounted) {
        setState(() {
          mesure = m;
          erreur = null;
        });
      }
    } catch (e) {
      if (mounted && mesure == null) {
        setState(() => erreur = '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  static String _k(num n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final texte = sombre ? const Color(0xFFEDEDF2) : const Color(0xFF1C1C21);
    final doux = sombre ? const Color(0xFF9B9BA8) : const Color(0xFF6B6B78);

    final tokens = (mesure?['tokens'] as num?) ?? 0;
    final seuil = (mesure?['seuil'] as num?) ?? 60000;
    final part = seuil > 0 ? (tokens / seuil).clamp(0.0, 1.0).toDouble() : 0.0;
    final Color couleur;
    final String verdict;
    if (mesure == null) {
      couleur = doux;
      verdict = erreur ?? 'Mesure en cours…';
    } else if (tokens >= seuil) {
      couleur = const Color(0xFFF25F5C);
      verdict = 'Contexte plein : demande la passation.';
    } else if (tokens >= seuil * 0.6) {
      couleur = const Color(0xFFF5A524);
      verdict = 'Encore un peu de place : petite tâche, ou prévois la passation.';
    } else {
      couleur = const Color(0xFF3DDC97);
      verdict = 'De la place : tu peux lui redonner du travail.';
    }
    final modele = (mesure?['modele'] ?? '').toString().split('/').last;

    final jauge = ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: mesure == null ? null : part,
        minHeight: 6,
        color: couleur,
        backgroundColor: couleur.withValues(alpha: 0.18),
      ),
    );

    return Material(
      color: couleur.withValues(alpha: sombre ? 0.10 : 0.08),
      child: InkWell(
        onTap: widget.replie ? () => setState(() => deplie = !deplie) : null,
        child: Container(
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: couleur.withValues(alpha: 0.35)))),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.memory_rounded, size: 16, color: couleur),
                const SizedBox(width: 6),
                Text('Contexte',
                    style: TextStyle(
                        color: texte, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 10),
                Expanded(child: jauge),
                const SizedBox(width: 10),
                Text(
                    mesure == null
                        ? '…'
                        : '${_k(tokens)} / ${_k(seuil)} · ${(part * 100).round()} %',
                    style: TextStyle(
                        color: texte,
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                if (widget.replie)
                  Icon(deplie ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18, color: doux),
              ]),
              if (deplie) ...[
                const SizedBox(height: 6),
                Text(verdict,
                    style: TextStyle(
                        color: couleur, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    [
                      'Seuil de passation : ${_k(seuil)} tokens',
                      if (modele.isNotEmpty) modele,
                      'mesuré au dernier tour, actualisé toutes les 30 s',
                    ].join(' · '),
                    style: TextStyle(color: doux, fontSize: 11.5)),
                if (widget.onPassation != null && mesure != null && part >= 0.6)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: couleur,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact),
                      onPressed: () => widget.onPassation!(kMessagePassation),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Demander la passation'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
