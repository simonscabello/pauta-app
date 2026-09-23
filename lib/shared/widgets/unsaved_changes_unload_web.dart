import 'dart:js_interop';

@JS('addEventListener')
external void _addEventListener(String type, JSFunction listener);

extension type _BeforeUnloadEvent(JSObject _) implements JSObject {
  external void preventDefault();
  external set returnValue(JSString value);
}

/// F5 ou fechar a aba com alteração por salvar: o navegador mostra a pergunta
/// dele ("Sair do site?"). O texto não é nosso — navegador nenhum deixa mais a
/// página escrever essa frase —, mas a pausa é o que importa.
///
/// Um ouvinte só, instalado uma vez, que consulta o registro de guardas a cada
/// disparo: ligar e desligar um ouvinte por tela arriscaria deixar um órfão
/// bloqueando a saída de uma página já salva.
void installBeforeUnloadGuard(bool Function() shouldBlock) {
  _addEventListener(
    'beforeunload',
    ((_BeforeUnloadEvent event) {
      if (!shouldBlock()) return;
      event.preventDefault();
      event.returnValue = ''.toJS;
    }).toJS,
  );
}
