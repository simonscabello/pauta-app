import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/date/report_period.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('período dos relatórios', () {
    test('os atalhos pedem meses e se escrevem como a equipe fala', () {
      expect(const ReportPeriodMonths(1).label, 'Último mês');
      expect(const ReportPeriodMonths(3).label, 'Últimos 3 meses');
      expect(const ReportPeriodMonths(3).phrase, 'nos últimos 3 meses');
      expect(const ReportPeriodMonths(1).phrase, 'no último mês');
      expect(const ReportPeriodMonths(6).toQuery(), {'months': 6});
    });

    test('o intervalo manda os dias civis, sem hora', () {
      final period = ReportPeriodRange(
        DateTime(2026, 3, 1, 15, 30),
        DateTime(2026, 6, 30, 8),
      );
      expect(period.toQuery(), {'from': '2026-03-01', 'to': '2026-06-30'});
    });

    test('o ano só aparece quando faz falta', () {
      final esteAno = DateTime.now().year;
      final dentro = ReportPeriodRange(
        DateTime(esteAno, 1, 1),
        DateTime(esteAno, 1, 31),
      );
      expect(dentro.label, isNot(contains('$esteAno')));

      final virada = ReportPeriodRange(
        DateTime(esteAno - 1, 12, 1),
        DateTime(esteAno, 1, 31),
      );
      expect(virada.label, contains('${esteAno - 1}'));
      expect(virada.label, contains('$esteAno'));
      expect(virada.phrase, startsWith('entre '));
    });

    test('o que as pontas têm em comum se escreve uma vez', () {
      final ano = DateTime.now().year;
      final mesmoMes =
          ReportPeriodRange(DateTime(ano, 9, 6), DateTime(ano, 9, 20));
      expect(mesmoMes.label, '6 – 20 de set.');
      // Na frase, por extenso: o abreviado termina em ponto, e "20 de set.."
      // no fim de uma frase era o que aparecia.
      expect(mesmoMes.phrase, 'entre 6 e 20 de setembro');

      final doisMeses =
          ReportPeriodRange(DateTime(ano, 8, 6), DateTime(ano, 9, 20));
      expect(doisMeses.label, '6 de ago. – 20 de set.');
      expect(doisMeses.phrase, 'entre 6 de agosto e 20 de setembro');

      final outroAno =
          ReportPeriodRange(DateTime(2025, 12, 6), DateTime(2026, 1, 20));
      expect(
        outroAno.phrase,
        'entre 6 de dezembro de 2025 e 20 de janeiro de 2026',
      );
    });

    test('um dia só é período ("como foi a Páscoa?")', () {
      final pascoa = ReportPeriodRange(
        DateTime(DateTime.now().year, 4, 5),
        DateTime(DateTime.now().year, 4, 5),
      );
      expect(pascoa.label, isNot(contains('–')));
      expect(pascoa.phrase, startsWith('em '));
    });

    test('igualdade por valor: o período é chave de provider', () {
      expect(const ReportPeriodMonths(3), const ReportPeriodMonths(3));
      expect(
        ReportPeriodRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31)),
        ReportPeriodRange(DateTime(2026, 3, 1, 12), DateTime(2026, 3, 31, 9)),
      );
      expect(
        ReportPeriodRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31)).hashCode,
        ReportPeriodRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31)).hashCode,
      );
      expect(const ReportPeriodMonths(3) == const ReportPeriodMonths(6), false);
    });
  });

  group('dia da semana', () {
    test('0 é domingo, como na grade de cultos', () {
      expect(weekdayPluralLabel(0), 'Domingos');
      expect(weekdayPluralLabel(4), 'Quintas');
      expect(weekdayFilterLabel(null), 'Todos os dias');
      expect(weekdayFilterLabel(4), 'Só quintas');
    });

    test('o artigo concorda com o dia', () {
      expect(weekdayPhrase(0), 'aos domingos');
      expect(weekdayPhrase(6), 'aos sábados');
      expect(weekdayPhrase(4), 'às quintas');
      expect(weekdayPhrase(null), isNull);
    });
  });
}
