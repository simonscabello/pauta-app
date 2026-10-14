import 'dart:js_interop';

/// `window.pautaWeb`, definido em `web/pauta-web.js`. Ausente (página sem o
/// script, teste) vira "não há" em tudo, como fora da Web.
@JS('pautaWeb')
external _PautaWeb? get _bridge;

extension type _PautaWeb(JSObject _) implements JSObject {
  external JSBoolean pushSupported();
  external JSBoolean pushNeedsInstall();
  external JSString pushPermission();
  external JSPromise<JSString> pushRequestPermission();
  external JSPromise<JSString?> pushSubscribe(JSString publicKey);
  external JSPromise<JSString?> pushCurrentSubscription();
  external void pushOnTap(JSFunction callback);
  external JSString? pushInitialTap();
  external void download(JSString name, JSString mime, JSString content);
}

bool pushSupported() => _bridge?.pushSupported().toDart ?? false;

bool pushNeedsInstall() => _bridge?.pushNeedsInstall().toDart ?? false;

String pushPermission() => _bridge?.pushPermission().toDart ?? 'unsupported';

Future<String> requestPushPermission() async {
  final bridge = _bridge;
  if (bridge == null) return 'unsupported';
  return (await bridge.pushRequestPermission().toDart).toDart;
}

Future<String?> pushSubscribe(String publicKey) async {
  final bridge = _bridge;
  if (bridge == null) return null;
  return (await bridge.pushSubscribe(publicKey.toJS).toDart)?.toDart;
}

Future<String?> pushCurrentSubscription() async {
  final bridge = _bridge;
  if (bridge == null) return null;
  return (await bridge.pushCurrentSubscription().toDart)?.toDart;
}

void onPushTap(void Function(String json) callback) {
  _bridge?.pushOnTap(((JSString json) => callback(json.toDart)).toJS);
}

String? takeInitialPushTap() => _bridge?.pushInitialTap()?.toDart;

bool download(String name, String mime, String content) {
  final bridge = _bridge;
  if (bridge == null) return false;
  bridge.download(name.toJS, mime.toJS, content.toJS);
  return true;
}
