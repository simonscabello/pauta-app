import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/onboarding/domain/leader_tour.dart';
import 'package:louvor_app/features/onboarding/domain/member_tour.dart';

/// Os alvos dos tours existem nas telas.
///
/// **Alvo removido não dá erro nenhum**: a parada só perde o destaque, o tour
/// espera 3 s no escuro e mostra o texto solto. Foi assim que a parada da
/// disponibilidade ficou sem destaque por semanas (09/2026). Este teste lê o
/// código das telas e falha quando um id dos tours não está envolvido por um
/// `TourTarget` em lugar nenhum — o lembrete de que mudar uma tela citada num
/// tour pede mudar o tour (e o guia do site) junto. Ver o mapa do conteúdo em
/// `docs/produto/onboarding.md`.
void main() {
  final declarados = _declaredIds();
  final envolvidos = _wrappedIds();

  test('todo id declarado está numa tela', () {
    for (final nome in declarados.keys) {
      expect(
        envolvidos,
        contains(nome),
        reason: 'TourTargetIds.$nome não está em nenhum TourTarget de lib/',
      );
    }
  });

  test('toda parada dos dois tours aponta para um id declarado', () {
    final valores = declarados.values.toSet();
    final paradas = [
      ...leaderTourSteps(),
      ...memberTourSteps(
        const MemberTourContext(nextScheduleId: 'e1', pushSupported: true),
      ),
    ];
    for (final parada in paradas) {
      final alvo = parada.target;
      if (alvo == null) continue;
      expect(valores, contains(alvo), reason: parada.title);
    }
  });

  test('o tour do líder anda pelas telas de montar a equipe', () {
    final paradas = leaderTourSteps();
    expect(paradas.map((p) => p.route), [
      '/equipe',
      '/equipe/cultos',
      '/equipe/integrantes',
      '/equipe/convites',
      '/equipe/musicas',
      '/agenda',
      '/inicio',
    ]);
    expect(paradas.every((p) => p.target != null), isTrue);
  });
}

/// `static const nome = 'valor';` dentro de `TourTargetIds`.
Map<String, String> _declaredIds() {
  final fonte = File(
    'lib/features/onboarding/domain/member_tour.dart',
  ).readAsStringSync();
  final classe = fonte.substring(
    fonte.indexOf('abstract final class TourTargetIds'),
    fonte.indexOf('class TourStep'),
  );
  return {
    for (final m in RegExp(r"static const (\w+) = '([^']+)'")
        .allMatches(classe))
      m.group(1)!: m.group(2)!,
  };
}

/// Os ids usados como `id: TourTargetIds.x` fora dos arquivos dos tours.
Set<String> _wrappedIds() {
  final ids = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('onboarding/domain/')) continue;
    final fonte = entity.readAsStringSync();
    for (final m in RegExp(r'id:\s*TourTargetIds\.(\w+)').allMatches(fonte)) {
      ids.add(m.group(1)!);
    }
  }
  return ids;
}
