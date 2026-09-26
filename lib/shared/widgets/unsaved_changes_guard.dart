import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import 'unsaved_changes_unload_stub.dart'
    if (dart.library.js_interop) 'unsaved_changes_unload_web.dart';

/// Pergunta antes de descartar o que a pessoa fez e ainda não salvou.
///
/// **Nenhum formulário do app tinha essa proteção**, e o preço apareceu na
/// tarefa mais longa da semana: três músicas escolhidas, tom, momento e recado
/// acertados, um toque na seta de voltar — e a escala abria com "Nenhuma música
/// escolhida ainda.", sem aviso.
///
/// Três caminhos tiram a pessoa de uma tela, e cada um precisa de um anteparo
/// próprio:
///
/// 1. **Voltar** (seta, gesto, botão do Android) — o [PopScope] daqui.
/// 2. **Navegar por fora** (barra lateral, barra inferior, voltar do
///    navegador) — o go_router troca a pilha sem perguntar ao [PopScope]. É o
///    `onExit` das rotas de formulário, [confirmLeaveIfUnsaved], que consulta
///    este mesmo registro.
/// 3. **Recarregar ou fechar a aba** na Web — o `beforeunload` do navegador,
///    que só aceita a pergunta genérica dele.
///
/// [isDirty] é uma **função**, e não um booleano, de propósito: quem salva e
/// navega em seguida atualiza a própria referência e sai no mesmo instante, e
/// um booleano lido no último `build` ainda diria "alterado" — a tela
/// perguntaria "sair sem salvar?" logo depois de salvar.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.confirmLeave = showDiscardChangesDialog,
  });

  final bool Function() isDirty;
  final Widget child;

  /// A pergunta feita antes de sair; `true` sai. O padrão é "Sair sem
  /// salvar?". Troca quando o que se perde não é uma edição — a chave de
  /// assistente de IA, mostrada uma vez só —, e os três anteparos continuam os
  /// mesmos: o `onExit` da rota usa a pergunta da tela que está alterada.
  final Future<bool> Function(BuildContext context) confirmLeave;

  /// Alguma tela aberta tem alteração por salvar?
  static bool get hasUnsavedChanges =>
      _UnsavedChangesGuardState._active.any((guard) => guard._dirty);

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  static final Set<_UnsavedChangesGuardState> _active = {};
  static bool _unloadInstalled = false;

  /// Depois de "Descartar alterações" a tela vai embora; perguntar de novo no
  /// `onExit` da rota seria a mesma pergunta duas vezes.
  bool _discarded = false;

  bool get _dirty => !_discarded && mounted && widget.isDirty();

  @override
  void initState() {
    super.initState();
    _active.add(this);
    if (!_unloadInstalled) {
      _unloadInstalled = true;
      installBeforeUnloadGuard(() => UnsavedChangesGuard.hasUnsavedChanges);
    }
  }

  @override
  void dispose() {
    _active.remove(this);
    super.dispose();
  }

  Future<void> _onBlockedPop() async {
    // `canPop` é do último `build`, e um campo de texto muda sem reconstruir a
    // tela: quem digitou e apagou chega aqui sem nada a perder.
    final leave = !_dirty || await widget.confirmLeave(context);
    if (!leave || !mounted) return;
    _discarded = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBlockedPop();
      },
      child: widget.child,
    );
  }

  static void _discardAll() {
    for (final guard in _active) {
      guard._discarded = true;
    }
  }
}

/// O "tem alteração?" dos formulários, num formato só.
///
/// A tela descreve em [unsavedSignature] tudo o que salvar mandaria, como
/// texto. [markUnsavedBaseline] fotografa esse texto quando o formulário fica
/// pronto (preenchido com o que veio do servidor, ou semeado pela grade), e
/// [markSaved] de novo logo depois de salvar — antes de navegar, senão a
/// própria saída pós-salvar perguntaria "sair sem salvar?".
///
/// Comparar o conteúdo, e não marcar "mexeu" a cada toque, é o que faz desfazer
/// à mão (apagar a letra digitada) contar como "não mudou nada".
mixin UnsavedChangesTracker<T extends StatefulWidget> on State<T> {
  String? _baseline;

  String unsavedSignature();

  /// Chamado a cada `build`; só a primeira chamada vale.
  void markUnsavedBaseline() => _baseline ??= unsavedSignature();

  void markSaved() => _baseline = unsavedSignature();

  bool hasUnsavedChanges() =>
      _baseline != null && unsavedSignature() != _baseline;
}

/// `onExit` das rotas de formulário: quando o go_router vai tirar a tela da
/// pilha por um caminho que não é o voltar (barra lateral, voltar do
/// navegador, um `go` de outro lugar), pergunta antes.
///
/// Sem alteração pendente responde na hora — é o caso de salvar e seguir para
/// o passo seguinte, que também tira a tela da pilha.
FutureOr<bool> confirmLeaveIfUnsaved(
  BuildContext context,
  GoRouterState state,
) async {
  final dirty = _UnsavedChangesGuardState._active
      .where((guard) => guard._dirty)
      .firstOrNull;
  if (dirty == null) return true;
  final leave = await dirty.widget.confirmLeave(context);
  if (leave) _UnsavedChangesGuardState._discardAll();
  return leave;
}

/// "Sair sem salvar?" — **continuar é o botão cheio**: o toque apressado cai
/// no que preserva o trabalho, e descartar exige ler.
///
/// Os textos mudam para quem perde outra coisa que não uma edição (ver
/// [UnsavedChangesGuard.confirmLeave]); a arrumação dos botões, não.
Future<bool> showDiscardChangesDialog(
  BuildContext context, {
  String title = 'Sair sem salvar?',
  String message =
      'O que você mudou nesta tela ainda não foi salvo e vai se perder.',
  String leaveLabel = 'Descartar alterações',
  String stayLabel = 'Continuar editando',
}) async {
  final scheme = Theme.of(context).colorScheme;
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(leaveLabel),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(stayLabel),
        ),
      ],
    ),
  );
  return leave ?? false;
}
