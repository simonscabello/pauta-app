import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/storage/read_cache.dart';
import '../domain/event_datetime.dart';
import '../domain/event_models.dart';
import 'event_repository.dart';

const agendaQueryLimit = 100;

/// Recorte inclusivo (`AAAA-MM-DD`) de um mês civil para
/// `GET /teams/:id/events?from=&to=`.
typedef AgendaMonthRange = ({String from, String to});

/// Chave do recorte mensal da agenda: equipe + mês civil (dia 1, sem hora).
typedef AgendaMonthQuery = (String teamId, DateTime month);

/// O mês civil (dia 1, sem hora) em que [instant] cai no fuso [timezone] da
/// equipe.
///
/// Importante na virada do mês: `2026-10-01T01:30:00Z` já é outubro em UTC,
/// mas ainda é `30/09 22:30` em `America/Sao_Paulo`, então o mês exibido para
/// a equipe continua sendo setembro.
DateTime agendaMonthInTimezone(DateTime instant, String timezone) {
  final local = eventLocalTime(
    instant,
    timezone.isEmpty ? 'America/Sao_Paulo' : timezone,
  );
  return DateTime(local.year, local.month);
}

/// Limites inclusivos `from` e `to` (`AAAA-MM-DD`) de um mês civil para
/// `GET /teams/:id/events?from=&to=`, que o servidor interpreta no fuso da
/// equipe.
///
/// Quando [timezone] é informado, [month] é tratado como instante e convertido
/// para o fuso da equipe antes de calcular o mês civil; quando omitido, usa
/// diretamente `month.year` e `month.month`.
AgendaMonthRange agendaMonthRange(DateTime month, {String? timezone}) {
  final resolved = timezone == null
      ? DateTime(month.year, month.month)
      : agendaMonthInTimezone(month, timezone);
  final first = DateTime(resolved.year, resolved.month, 1);
  final last = DateTime(resolved.year, resolved.month + 1, 0);
  return (from: dateKey(first), to: dateKey(last));
}

/// As escalas de um mês civil inteiro (`GET /teams/:id/events?from=&to=`),
/// com cache offline por recorte.
///
/// Substitui a antiga consulta `scope=past` da agenda: navegar para trás (ou
/// para meses futuros além das próximas 20) pede apenas o mês exibido, sem
/// ampliar listas de 20 para 100 itens.
final agendaMonthProvider = FutureProvider.autoDispose
    .family<CachedValue<List<Event>>, AgendaMonthQuery>((ref, query) {
  final (teamId, month) = query;
  final range = agendaMonthRange(month);
  return ref.watch(eventRepositoryProvider).listRange(
        teamId,
        from: range.from,
        to: range.to,
      );
});

/// Invalida as listas de escalas usadas pela Home e pela Agenda:
/// `upcoming` (reaproveitado pela Home) e todos os recortes mensais ativos.
void invalidateAgendaSchedules(WidgetRef ref, String teamId) {
  ref.invalidate(eventsProvider((teamId, 'upcoming')));
  ref.invalidate(agendaMonthProvider);
}
