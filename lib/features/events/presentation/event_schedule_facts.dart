import 'package:flutter/widgets.dart';

import '../domain/event_datetime.dart';
import '../domain/event_models.dart';

/// Os fatos de uma escala, já escritos.
///
/// **Existe porque a mesma frase estava sendo montada em três lugares.** A
/// manchete, a linha da lista e o texto compartilhado juntavam rótulo, hora e
/// ensaio cada um do seu jeito; bastou o ensaio ganhar o dia abreviado para as
/// três divergirem. Aqui a regra é uma só, e quem desenha escolhe a forma —
/// [times] e [rehearsal] separados para a manchete, [summary] em linha única
/// para a lista.
///
/// Só formata: nenhuma decisão sobre **o que** mostrar mora aqui.
class ScheduleFacts {
  const ScheduleFacts({
    required this.times,
    required this.rehearsal,
    required this.songs,
  });

  /// Os horários dos cultos.
  ///
  /// Com um culto só, a hora limpa ("19:30"): o rótulo da grade é quase sempre
  /// "Culto", e "Culto 19:30" gasta uma palavra para não dizer nada. Com dois
  /// ou mais, o rótulo passa a ser a única coisa que os distingue.
  final String times;

  /// "Sem ensaio", "Ensaio 10:30", "Ensaio sáb 19:00".
  ///
  /// A ausência é informação, e não vazio: quem recebe a escala precisa saber
  /// que não há ensaio, em vez de deduzir da linha que falta.
  final String rehearsal;

  /// O estado do repertório, ou `null` quando não há o que dizer.
  ///
  /// **Sem saber, cala.** Na listagem da agenda o `songCount` de cada culto é a
  /// única fonte, e ele vem nulo em cache gravado antes de o campo existir —
  /// ali "não sei" e "não tem" teriam a mesma cara, e marcar como pendente toda
  /// escala montada que o app ainda não recarregou é pior do que calar.
  final String? songs;

  /// Tudo numa linha: "Manhã 08:30 · Noite 19:00 · Ensaio sáb 19:00".
  ///
  /// **Na linha da lista, o ensaio só entra quando existe.** "Sem ensaio" em
  /// quase toda linha da agenda era a mesma palavra repetida dez vezes, e
  /// tirava o olho do que muda de uma escala para a outra. Na manchete e no
  /// detalhe a ausência continua dita ([rehearsal]).
  String get summary =>
      rehearsal == _noRehearsal ? times : '$times · $rehearsal';

  static const _noRehearsal = 'Sem ensaio';

  static ScheduleFacts of(Event event, String timezone) {
    final services = event.displayServices;

    final times = services.length == 1
        ? formatEventTime(services.first.startsAt, timezone)
        : [
            for (final service in services)
              '${service.label} '
                  '${formatEventTime(service.startsAt, timezone)}',
          ].join(' · ');

    final rehearsalAt = event.rehearsalAt;
    final rehearsal = rehearsalAt == null
        ? _noRehearsal
        // Com o dia abreviado quando o ensaio é em outro dia: só a hora fazia
        // um ensaio de sábado parecer ser no dia do culto.
        : 'Ensaio ${formatRehearsalTime(
            rehearsalAt,
            event.startsAt,
            timezone,
          )}';

    return ScheduleFacts(
      times: times,
      rehearsal: rehearsal,
      songs: _songs(event),
    );
  }

  static String? _songs(Event event) {
    // Dito, e não calado: a escala sem lista de músicas precisa distinguir "as
    // músicas ainda não saíram" de "não vai ter lista" -- e é essa distinção
    // que o modo de repertório existe para carregar.
    if (event.isRepertoireOnTheFly) return 'Repertório definido na hora';

    final semRepertorio = event.servicesWithoutSongs;
    if (semRepertorio.isNotEmpty) {
      // Sem nenhuma música, nomear os cultos só repetiria a linha de horários.
      return event.hasNoSongs
          ? 'Músicas a definir'
          : 'Músicas a definir: ${semRepertorio.join(' e ')}';
    }

    // Nenhum culto pendente pode ser "todos montados" ou "não faço ideia". O
    // segundo é o cache antigo, e ali a resposta é o silêncio.
    final sabe = event.songs.isNotEmpty ||
        event.displayServices.any((service) => service.songCount != null);
    return sabe ? 'Repertório definido' : null;
  }
}

/// A data da manchete, quebrada onde a leitura pede.
///
/// **A quebra é forçada depois da vírgula** — "Quinta-feira," numa linha e "10
/// de setembro" na outra. Deixada ao acaso, a linha estourava em lugares
/// diferentes a cada data ("Quinta-feira, 10 de / setembro" numa semana,
/// "Domingo, 13 de setembro" inteiro na outra), e a manchete mudava de forma
/// sem que nada tivesse mudado.
///
/// **Menos com a fonte do sistema aumentada.** Ali "Quinta-feira," já não cabe
/// sozinho numa linha: forçar a quebra gasta duas linhas com o dia da semana e
/// empurra "10 de setembro" para fora do limite — a data aparecia cortada como
/// "10 de set…", e a data é o que identifica a escala. Acima de ~1,25x o texto
/// se arruma melhor sozinho.
String heroDateText(BuildContext context, String date) {
  final apertado = MediaQuery.textScalerOf(context).scale(32) > 40;
  return apertado ? date : date.replaceFirst(', ', ',\n');
}
