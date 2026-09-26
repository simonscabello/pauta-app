import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/date/report_period.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/workload_report.dart';
import 'package:louvor_app/features/team/presentation/workload_report_screen.dart';
import 'package:louvor_app/shared/widgets/app_date_range_picker.dart';

WorkloadReport _relatorio({int? weekday}) => WorkloadReport.fromJson({
      'months': 3,
      'from': '2026-06-26',
      'to': '2026-09-26',
      'since': '2026-06-26T12:00:00.000Z',
      'until': '2026-09-26T12:00:00.000Z',
      'weekday': weekday,
      'weekdays': [
        {'weekday': 0, 'count': 9},
        {'weekday': 4, 'count': 3},
      ],
      'scheduleTotal': 12,
      'positions': [
        {'positionId': 'violao', 'name': 'Violão'},
        {'positionId': 'vocal', 'name': 'Vocal'},
      ],
      'members': [
        {
          'membershipId': 'simon',
          'displayName': 'Simon',
          'scheduleCount': 2,
          'unavailableCount': 6,
          'positionIds': ['violao', 'vocal'],
          'positions': [
            {'positionId': 'vocal', 'name': 'Vocal', 'count': 2},
          ],
        },
        {
          'membershipId': 'gerson',
          'displayName': 'Gerson',
          'scheduleCount': 8,
          'positionIds': ['violao'],
          'positions': [
            {
              'positionId': 'violao',
              'name': 'Violão',
              'count': 8,
              'lastScheduledAt': '2026-09-20T12:00:00.000Z',
            },
          ],
        },
        {
          'membershipId': 'josy',
          'displayName': 'Josy',
          'scheduleCount': 5,
          'positionIds': ['vocal'],
          'positions': [
            {'positionId': 'vocal', 'name': 'Vocal', 'count': 5},
          ],
        },
      ],
    });

void _telaDeCelular(WidgetTester tester) {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// O item do menu, e não o texto: o texto do `CheckedPopupMenuItem` fica
/// atrás de uma camada que recebe o toque no lugar dele.
Finder _itemDoMenu(String texto) => find.ancestor(
      of: find.text(texto),
      matching: find.byType(CheckedPopupMenuItem<int>),
    );

double _alturaDe(WidgetTester tester, String texto) =>
    tester.getTopLeft(find.text(texto)).dy;

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('participação', () {
    Future<List<WorkloadQuery>> montar(WidgetTester tester) async {
      _telaDeCelular(tester);
      final pedidos = <WorkloadQuery>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workloadProvider.overrideWith((ref, query) async {
              pedidos.add(query);
              return _relatorio(weekday: query.weekday);
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const WorkloadReportScreen(teamId: 't1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return pedidos;
    }

    testWidgets('abre em 3 meses, com quem mais serviu primeiro', (
      tester,
    ) async {
      final pedidos = await montar(tester);

      expect(pedidos.single.period, const ReportPeriodMonths(3));
      expect(find.text('Últimos 3 meses'), findsOneWidget);
      expect(_alturaDe(tester, 'Gerson'), lessThan(_alturaDe(tester, 'Josy')));
      expect(_alturaDe(tester, 'Josy'), lessThan(_alturaDe(tester, 'Simon')));
      // O motivo do número baixo vem na linha.
      expect(find.textContaining('não pôde em 6'), findsOneWidget);
    });

    testWidgets('a função traz quem sabe tocar e não tocou', (tester) async {
      await montar(tester);

      await tester.tap(find.text('Violão').first);
      await tester.pumpAndSettle();

      expect(find.text('Gerson'), findsOneWidget);
      expect(find.text('Simon'), findsOneWidget);
      expect(find.text('Josy'), findsNothing);
      expect(find.text('0 escalas'), findsOneWidget);
      expect(
        find.textContaining('não apareceu em Violão no período'),
        findsOneWidget,
      );
    });

    testWidgets('o período e o dia da semana vão na consulta', (tester) async {
      final pedidos = await montar(tester);

      await tester.tap(find.text('Todos os dias'));
      await tester.pumpAndSettle();
      await tester.tap(_itemDoMenu('Quintas · 3 escalas'));
      await tester.pumpAndSettle();
      expect(pedidos.last.weekday, 4);
      expect(find.text('Só quintas'), findsOneWidget);

      await tester.tap(find.text('Últimos 3 meses'));
      await tester.pumpAndSettle();
      await tester.tap(_itemDoMenu('Últimos 12 meses'));
      await tester.pumpAndSettle();
      expect(pedidos.last.period, const ReportPeriodMonths(12));
      // O dia da semana continua escolhido ao trocar o período.
      expect(pedidos.last.weekday, 4);
    });
  });

  group('seletor de período', () {
    testWidgets('dois toques escolhem o período, em qualquer ordem', (
      tester,
    ) async {
      _telaDeCelular(tester);
      DateTimeRange? range;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  range = await showAppDateRangePicker(
                    context: context,
                    lastDate: DateTime(2026, 9, 26),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Toque no primeiro dia do período.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('periodo-2026-09-20')));
      await tester.pump();
      // Tocar antes do começo inverte as pontas, em vez de recomeçar.
      await tester.tap(find.byKey(const ValueKey('periodo-2026-09-06')));
      await tester.pump();
      // Depois do último dia não responde.
      await tester.tap(find.byKey(const ValueKey('periodo-2026-09-28')));
      await tester.pump();

      await tester.tap(find.text('Ver este período'));
      await tester.pumpAndSettle();

      expect(range!.start, DateTime(2026, 9, 6));
      expect(range!.end, DateTime(2026, 9, 20));
    });
  });
}
