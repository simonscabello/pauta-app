import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/onboarding/data/onboarding_repository.dart';
import 'package:louvor_app/features/onboarding/domain/member_tour.dart';
import 'package:louvor_app/features/onboarding/domain/onboarding_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A regra de oferta e o caminho do tour, sem widget nenhum.
///
/// O que quebraria calado: a versão nova não reaparecer para quem viu a
/// anterior, "Agora não" não contar como resposta, e a parada das músicas
/// apontar para uma escala que não é da pessoa.
void main() {
  group('quando oferecer', () {
    const v1 = OnboardingFlows.member;
    const v2 = OnboardingFlow('member_onboarding', 2);

    test('ninguém respondeu: oferece', () {
      expect(
        shouldOfferOnboarding(v1, records: const [], pendingLocally: false),
        isTrue,
      );
    });

    test('concluir ou pular encerram a oferta', () {
      for (final outcome in OnboardingOutcome.values) {
        expect(
          shouldOfferOnboarding(
            v1,
            records: [OnboardingRecord(flow: v1, outcome: outcome)],
            pendingLocally: false,
          ),
          isFalse,
          reason: outcome.name,
        );
      }
    });

    test('a versão 2 volta a aparecer para quem viu a 1', () {
      expect(
        shouldOfferOnboarding(
          v2,
          records: const [
            OnboardingRecord(flow: v1, outcome: OnboardingOutcome.completed),
          ],
          pendingLocally: false,
        ),
        isTrue,
      );
    });

    test('outro assunto não conta', () {
      expect(
        shouldOfferOnboarding(
          v1,
          records: const [
            OnboardingRecord(
              flow: OnboardingFlow('leader_onboarding', 1),
              outcome: OnboardingOutcome.completed,
            ),
          ],
          pendingLocally: false,
        ),
        isTrue,
      );
    });

    test('a resposta presa no aparelho também encerra', () {
      expect(
        shouldOfferOnboarding(v1, records: const [], pendingLocally: true),
        isFalse,
      );
    });
  });

  group('o registro', () {
    test('lê a resposta do servidor', () {
      final record = OnboardingRecord.fromJson(const {
        'key': 'member_onboarding_v1',
        'flow': 'member_onboarding',
        'version': 1,
        'status': 'SKIPPED',
        'finishedAt': '2026-09-17T12:00:00.000Z',
      });

      expect(record.flow, OnboardingFlows.member);
      expect(record.outcome, OnboardingOutcome.skipped);
    });

    test('a chave vai e volta', () {
      expect(OnboardingFlows.member.key, 'member_onboarding_v1');
      expect(
        parseOnboardingKey('member_onboarding_v1'),
        OnboardingFlows.member,
      );
      expect(
        parseOnboardingKey('leader_onboarding_v12'),
        const OnboardingFlow('leader_onboarding', 12),
      );
      expect(parseOnboardingKey('sem_versao'), isNull);
    });

    test('a pendência é por pessoa e sai depois de entregue', () async {
      SharedPreferences.setMockInitialValues({});
      final pending = PendingOnboardings(await SharedPreferences.getInstance());

      await pending.add(
        'u1',
        OnboardingFlows.member,
        OnboardingOutcome.completed,
      );

      expect(pending.contains('u1', OnboardingFlows.member), isTrue);
      expect(pending.contains('u2', OnboardingFlows.member), isFalse);
      expect(pending.entries('u1'), [
        (OnboardingFlows.member, OnboardingOutcome.completed),
      ]);

      await pending.remove('u1', OnboardingFlows.member);
      expect(pending.contains('u1', OnboardingFlows.member), isFalse);
    });
  });

  group('o caminho do tour', () {
    List<TourStep> steps({String? next, bool push = false}) => memberTourSteps(
          MemberTourContext(nextScheduleId: next, pushSupported: push),
        );

    test('seis paradas, na ordem da semana', () {
      expect(steps(next: 'e1').map((s) => s.title), [
        'Sua próxima escala',
        'Músicas da escala',
        'Informe sua disponibilidade',
        'Agenda da equipe',
        'Repertório e sugestões',
        'Avisos no celular',
      ]);
      expect(steps().length, 6);
    });

    test('com escala, as músicas são as da minha escala', () {
      final musicas = steps(next: 'e1')[1];
      expect(musicas.route, '/agenda/e1');
      expect(musicas.target, TourTargetIds.eventSongs);
    });

    test('sem escala, as músicas se explicam pela manchete da Home', () {
      final musicas = steps()[1];
      expect(musicas.route, '/inicio');
      expect(musicas.target, TourTargetIds.homeNext);
      expect(steps()[0].body, contains('Quando você for escalado'));
    });

    test('disponibilidade: uma parada, na porta da Home', () {
      final all = steps();
      expect(all[2].route, '/inicio');
      expect(all[2].target, TourTargetIds.homeAvailability);
      expect(all.any((s) => s.route == '/disponibilidade'), isFalse);
    });

    test('sem push no aparelho, os avisos não apontam para interruptor', () {
      expect(steps().last.target, isNull);
      expect(steps().last.route, isNull);
      expect(steps(push: true).last.target, TourTargetIds.profilePush);
      expect(steps(push: true).last.route, '/perfil');
    });
  });
}
