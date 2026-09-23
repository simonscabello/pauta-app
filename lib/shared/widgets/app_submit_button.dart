import 'package:flutter/material.dart';

/// Quanto tempo a tela recém-aberta ignora o botão principal.
///
/// Criar uma escala encadeia três telas com o botão principal **no mesmo
/// lugar** ("Criar escala", "Salvar e escolher músicas", "Salvar e ver a
/// escala", "Publicar"). Na Web a troca é instantânea, e o segundo clique de
/// um clique duplo caía no botão da tela seguinte: a escala ia para o detalhe
/// sem repertório. Um toque nos primeiros instantes de uma tela nova não pode
/// ter sido dirigido a ela — ninguém lê e decide em 600 ms.
const kArrivalTapShield = Duration(milliseconds: 600);

/// O botão que salva, com o estado de "salvando" embutido.
///
/// Estava copiado em nove formulários, sempre assim: um ternário trocando o
/// rótulo por um `CircularProgressIndicator` de 20px. Duas coisas escapavam na
/// cópia — o botão continuava anunciando o rótulo antigo para o leitor de tela
/// enquanto girava, e nada impedia o segundo toque enquanto a primeira
/// requisição estava no ar.
///
/// A **largura não muda** ao entrar em carregamento: o rótulo continua ocupando
/// o lugar dele, invisível, com a rodinha por cima. Sem isso, "Criar escala"
/// virava um botão estreito e o dedo que já estava indo tocava fora.
class AppSubmitButton extends StatelessWidget {
  const AppSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.loadingLabel = 'Salvando',
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  /// O que o leitor de tela anuncia enquanto a requisição está no ar.
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: loading ? 0 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onPrimary,
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      enabled: !loading && onPressed != null,
      label: loading ? loadingLabel : label,
      excludeSemantics: true,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: content,
      ),
    );
  }
}
