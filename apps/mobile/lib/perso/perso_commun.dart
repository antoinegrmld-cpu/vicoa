// Vicoa Perso — petits éléments visuels partagés (pastille d'état, « il y a … »).

import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_theme.dart';
import 'perso_store.dart';

Color couleurStatut(BuildContext context, String statut) {
  final t = FlutterFlowTheme.of(context);
  switch (statut) {
    case 'ACTIVE':
    case 'STARTING':
      return t.success;
    case 'AWAITING_INPUT':
      return t.warning;
    case 'FAILED':
    case 'KILLED':
      return t.error;
    default:
      return t.secondaryText;
  }
}

String libelleStatut(String statut) {
  switch (statut) {
    case 'STARTING':
      return 'démarre';
    case 'ACTIVE':
      return 'travaille';
    case 'AWAITING_INPUT':
      return 'attend ta réponse';
    case 'PAUSED':
      return 'en pause';
    case 'COMPLETED':
    case 'REVIEWED':
      return 'terminé';
    case 'FAILED':
      return 'échec';
    case 'KILLED':
      return 'arrêté';
    case 'DISCONNECTED':
    case 'STALE':
      return 'déconnecté';
    default:
      return statut.toLowerCase();
  }
}

/// État d'un projet : vert si un agent travaille, orange si un agent attend, gris sinon.
String statutProjet(ProjetPerso p) {
  final statuts = p.sessions.map(statutDe).toSet();
  if (statuts.contains('ACTIVE') || statuts.contains('STARTING')) {
    return 'ACTIVE';
  }
  if (statuts.contains('AWAITING_INPUT')) return 'AWAITING_INPUT';
  if (statuts.contains('FAILED')) return 'FAILED';
  return 'COMPLETED';
}

String ilYA(DateTime? d) {
  if (d == null) return 'jamais';
  final ecart = DateTime.now().toUtc().difference(d.toUtc());
  if (ecart.inMinutes < 1) return "à l'instant";
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  if (ecart.inDays < 30) return 'il y a ${ecart.inDays} j';
  return 'il y a ${ecart.inDays ~/ 30} mois';
}

class Pastille extends StatelessWidget {
  const Pastille({super.key, required this.statut, this.taille = 10});
  final String statut;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final c = couleurStatut(context, statut);
    final vivant = statut == 'ACTIVE' || statut == 'STARTING';
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: vivant
            ? [
                BoxShadow(
                    color: c.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1)
              ]
            : null,
      ),
    );
  }
}
