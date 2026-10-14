import 'web_bridge_stub.dart'
    if (dart.library.js_interop) 'web_bridge_web.dart' as impl;

/// O que só o navegador sabe fazer: os avisos (Web Push) e baixar um arquivo.
///
/// Fora da Web tudo aqui responde "não há" e não faz nada -- o Android tem o
/// FCM e a folha de compartilhar. A implementação de verdade está em
/// `web/pauta-web.js`; este arquivo e o `_web` só a chamam.
abstract final class WebBridge {
  /// O navegador sabe receber aviso (service worker + Push API).
  static bool get pushSupported => impl.pushSupported();

  /// iPhone/iPad fora da tela de início: o Safari só entrega aviso para o
  /// Pauta instalado como app.
  static bool get pushNeedsInstall => impl.pushNeedsInstall();

  /// `granted`, `denied`, `default` ou `unsupported`.
  static String get pushPermission => impl.pushPermission();

  /// Pede a permissão. **Precisa vir de um toque**: o Safari recusa o pedido
  /// que não nasce de um gesto da pessoa.
  static Future<String> requestPushPermission() => impl.requestPushPermission();

  /// A assinatura deste navegador (JSON), criando-a se preciso. Nulo sem
  /// permissão ou sem suporte.
  static Future<String?> pushSubscribe(String publicKey) =>
      impl.pushSubscribe(publicKey);

  /// A assinatura que já existe, sem criar outra.
  static Future<String?> pushCurrentSubscription() =>
      impl.pushCurrentSubscription();

  /// Toques em avisos com o app aberto (o service worker manda para a aba).
  static void onPushTap(void Function(String json) callback) =>
      impl.onPushTap(callback);

  /// O toque que abriu o app, uma vez.
  static String? takeInitialPushTap() => impl.takeInitialPushTap();

  /// Baixa um arquivo de texto. Fora da Web, `false`: quem chama usa a folha
  /// de compartilhar.
  static bool download(String name, String mime, String content) =>
      impl.download(name, mime, content);
}
