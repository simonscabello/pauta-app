// Fora da Web: nada disto existe. Ver `web_bridge.dart`.

bool pushSupported() => false;
bool pushNeedsInstall() => false;
String pushPermission() => 'unsupported';
Future<String> requestPushPermission() async => 'unsupported';
Future<String?> pushSubscribe(String publicKey) async => null;
Future<String?> pushCurrentSubscription() async => null;
void onPushTap(void Function(String json) callback) {}
String? takeInitialPushTap() => null;
bool download(String name, String mime, String content) => false;
