import 'package:flutter/material.dart';

import '../core_bridge/core_bridge.dart';

/// The connection summary that proves the 7-day test.
class ConnectionReportView extends StatelessWidget {
  const ConnectionReportView({super.key, required this.report});

  final ConnectionReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r.since == 0) return const Text('Sem dados de conexão ainda.');
    final pct = r.totalMs == 0 ? 100.0 : r.connectedMs * 100 / r.totalMs;
    const sources = {
      'app': 'app',
      'system': 'sistema',
      'boot': 'celular ligado',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Medindo desde ${dateTime(r.since)}'),
        Text(
          'Conectado ${pct.toStringAsFixed(1).replaceAll('.', ',')}% do tempo '
          '(${duration(r.connectedMs)} de ${duration(r.totalMs)})',
        ),
        Text(
          r.drops == 0
              ? 'Quedas: nenhuma'
              : 'Quedas: ${r.drops} · mais longa: ${duration(r.longestMs)}',
        ),
        Text(
          'Inícios: ${[for (final MapEntry(:key, :value) in r.starts.entries) '${sources[key] ?? key} $value'].join(' · ')}',
        ),
        for (final o in r.outages) Text(outageLine(o)),
      ],
    );
  }
}

/// "01/10 14:05".
String dateTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

/// "menos de 1 min", "12 min", "3 h 05 min", "2 d 4 h".
String duration(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 1) return 'menos de 1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return '$hours h ${(minutes % 60).toString().padLeft(2, '0')} min';
  }
  return '${hours ~/ 24} d ${hours % 24} h';
}

/// One outage: when, how long and why.
String outageLine(Outage o) {
  final cause = switch (o.cause) {
    'drop' => 'caiu',
    'restart' => switch (o.source) {
      'system' => 'app reiniciado pelo sistema',
      'boot' => 'celular reiniciado',
      _ => 'app reiniciado',
    },
    _ => 'desligado de propósito',
  };
  final now = o.ongoing ? ' (agora)' : '';
  return '${dateTime(o.start)} · ${duration(o.durationMs)} · $cause$now';
}
