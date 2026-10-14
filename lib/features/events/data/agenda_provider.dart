import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/read_cache.dart';
import '../domain/event_models.dart';
import 'event_repository.dart';

const agendaQueryLimit = 100;

/// Reaproveita a consulta/cache da Home e as invalidações dos formulários.
/// Só amplia a leitura quando a primeira página pode estar incompleta.
/// As escalas de um mês inteiro, para quando o calendário mostra um mês que as
/// listas de próximas e passadas não cobrem (as 100 mais recentes já ficaram
/// para trás). O mês vai como o primeiro dia dele.
///
/// Observa as duas listas para ser refeito junto com elas: uma escala apagada
/// ou editada invalida a lista, e o mês não pode ficar com a versão antiga.
final agendaMonthProvider = FutureProvider.autoDispose
    .family<List<Event>, (String, DateTime)>((ref, query) async {
  final (teamId, month) = query;
  await Future.wait([
    ref.watch(eventsProvider((teamId, 'upcoming')).future),
    ref.watch(eventsProvider((teamId, 'past')).future),
  ]);
  String two(int n) => n.toString().padLeft(2, '0');
  final last = DateTime(month.year, month.month + 1, 0).day;
  return ref.watch(eventRepositoryProvider).listRange(
        teamId,
        from: '${month.year}-${two(month.month)}-01',
        to: '${month.year}-${two(month.month)}-${two(last)}',
      );
});

final agendaEventsProvider = FutureProvider.autoDispose
    .family<CachedValue<List<Event>>, EventsQuery>((ref, query) async {
  final initial = await ref.watch(eventsProvider(query).future);
  if (initial.data.length < 20 || initial.fromCache) return initial;
  return ref.watch(eventRepositoryProvider).list(
        query.$1,
        scope: query.$2,
        limit: agendaQueryLimit,
      );
});
