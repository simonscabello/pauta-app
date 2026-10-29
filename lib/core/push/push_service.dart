import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../platform/web_bridge.dart';

/// O canal em que o aviso aparece no Android.
///
/// **Precisa ser identico ao `ANDROID_CHANNEL_ID` do backend**
/// (`push.service.ts`): id diferente faz a mensagem chegar e nao aparecer, sem
/// erro em lugar nenhum.
const androidChannelId = 'escalas';

const _androidChannel = AndroidNotificationChannel(
  androidChannelId,
  'Escalas',
  // Só a descrição tem acento: o id acima precisa bater com o backend.
  description: 'Publicação da escala, trocas, repertório e sugestões.',
  importance: Importance.high,
);

/// O que o backend manda em `data`: para onde ir e de que equipe e o assunto.
class PushTap {
  const PushTap({required this.route, required this.teamId, required this.kind});

  final String route;
  final String teamId;
  final String kind;

  static PushTap? fromData(Map<String, dynamic> data) {
    final route = data['route'];
    final teamId = data['teamId'];
    if (route is! String || route.isEmpty) return null;
    return PushTap(
      route: route,
      teamId: teamId is String ? teamId : '',
      kind: data['kind'] is String ? data['kind'] as String : '',
    );
  }
}

/// Recebida com o app em segundo plano ou fechado.
///
/// **Nao desenha nada**: quando a mensagem traz `notification`, quem desenha e
/// o proprio Android. Este ponto de entrada existe porque o plugin exige um
/// handler registrado.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// O aparelho: permissao, canal, token e o toque que chega.
///
/// **Nao navega e nao conhece a arvore de rotas.** Quem leva o toque ate a
/// tela e o [PushCoordinator]; separar os dois deixa esta classe testavel e
/// mantem a decisao de "trocar de equipe antes de navegar" num lugar so.
///
/// Tudo aqui **degrada em silencio**: sem `google-services.json`, sem Google
/// Play Services ou na Web, o app continua inteiro -- so nao avisa.
///
/// Plano: docs/superpowers/plans/2026-09-08-notificacoes.md
class PushService {
  PushService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<PushTap>.broadcast();

  FirebaseMessaging? _messaging;
  bool _ready = false;

  /// A chave publica do Web Push, que o servidor entrega. Sem ela o
  /// navegador nao assina, e o aviso na Web fica desligado.
  String? _webPushKey;

  /// Android (FCM) e navegador com service worker e Push API (Web Push). No
  /// iPhone, so com o Pauta adicionado a tela de inicio -- ver
  /// [needsInstallForPush]. O desktop nativo nao tem para onde entregar.
  static bool get isSupported => _isAndroid || (kIsWeb && WebBridge.pushSupported);

  /// iPhone no Safari, fora da tela de inicio: o aviso existe, mas so depois
  /// de instalar. A tela explica em vez de esconder o assunto.
  static bool get needsInstallForPush => kIsWeb && WebBridge.pushNeedsInstall;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// O aviso chega pelo navegador, e nao por um app instalado: muda o nome
  /// que a tela da ao aparelho ("neste navegador") e onde se desbloqueia.
  static bool get isBrowser => kIsWeb;

  /// A resposta do navegador ao pedido de aviso: `granted`, `denied`,
  /// `default` (ainda não perguntado) ou `unsupported`.
  static String get browserPermission =>
      kIsWeb ? WebBridge.pushPermission : 'unsupported';

  /// Como o servidor chama este tipo de aparelho. O app da Play tem nome
  /// próprio para não receber o aviso de baixar o APK novo.
  String get platform => kIsWeb
      ? 'web'
      : AppConfig.isPlayStore
          ? 'android-play'
          : 'android';

  /// Na Web, o pedido de permissao precisa nascer de um toque (o Safari
  /// recusa o que nao nasce). A tela oferece um botao em vez de perguntar
  /// sozinha.
  static bool get permissionNeedsGesture => kIsWeb;

  /// Recebe a chave publica do servidor. `null` desliga o aviso no navegador.
  void setWebPushKey(String? key) {
    _webPushKey = key == null || key.isEmpty ? null : key;
  }

  bool get hasWebPushKey => _webPushKey != null;

  bool get isReady => _ready;

  /// Toques em avisos, venham do Android ou da notificacao que o proprio app
  /// desenhou enquanto estava aberto.
  Stream<PushTap> get onTap => _taps.stream;

  /// Prepara o SDK e o canal. Chamado uma vez, no boot.
  ///
  /// **Nao pede permissao** -- ver [requestPermission].
  Future<void> init() async {
    if (!isSupported || _ready) return;
    if (kIsWeb) {
      WebBridge.onPushTap(_addTapJson);
      _ready = true;
      return;
    }
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          final tap = PushTap.fromData(
            jsonDecode(payload) as Map<String, dynamic>,
          );
          if (tap != null) _taps.add(tap);
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      _messaging = FirebaseMessaging.instance;

      // Com o app aberto o FCM **nao desenha nada**. Sem esta linha o aviso
      // some justamente para quem esta com o app na mao -- o caso mais facil
      // de testar e o mais facil de dar como quebrado.
      FirebaseMessaging.onMessage.listen(_showWhileOpen);

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final tap = PushTap.fromData(message.data);
        if (tap != null) _taps.add(tap);
      });

      _ready = true;
    } catch (error) {
      debugPrint('Push indisponivel: $error');
    }
  }

  /// O aviso que abriu o app quando ele estava fechado.
  Future<PushTap?> initialTap() async {
    if (kIsWeb) {
      final json = WebBridge.takeInitialPushTap();
      return json == null ? null : _tapFromJson(json);
    }
    final message = await _messaging?.getInitialMessage();
    if (message == null) return null;
    return PushTap.fromData(message.data);
  }

  /// Pede a permissao do Android 13+.
  ///
  /// **Chamada depois de a pessoa ver a primeira escala**, e nao no primeiro
  /// boot: quem ainda nao sabe o que o app faz nao tem como decidir se quer
  /// ser avisado, e um "nao" dado ali e caro -- o sistema so volta a
  /// perguntar uma vez.
  Future<bool> requestPermission() async {
    if (kIsWeb) {
      return await WebBridge.requestPushPermission() == 'granted';
    }
    final messaging = _messaging;
    if (messaging == null) return false;
    try {
      final settings = await messaging.requestPermission();
      return _granted(settings);
    } catch (error) {
      debugPrint('Falha ao pedir permissao de notificacao: $error');
      return false;
    }
  }

  Future<bool> hasPermission() async {
    if (kIsWeb) return WebBridge.pushPermission == 'granted';
    final messaging = _messaging;
    if (messaging == null) return false;
    try {
      return _granted(await messaging.getNotificationSettings());
    } catch (_) {
      return false;
    }
  }

  /// O token deste aparelho, ou nulo quando nao ha push.
  ///
  /// No Android o token existe mesmo sem a permissao concedida -- ela controla
  /// a **exibicao**, nao a entrega. Por isso o registro no servidor acontece
  /// ao entrar na conta, e nao depois de pedir permissao.
  Future<String?> currentToken() async {
    if (kIsWeb) {
      final key = _webPushKey;
      if (key == null) return WebBridge.pushCurrentSubscription();
      return WebBridge.pushSubscribe(key);
    }
    final messaging = _messaging;
    if (messaging == null) return null;
    try {
      return await messaging.getToken();
    } catch (error) {
      debugPrint('Falha ao obter o token do aparelho: $error');
      return null;
    }
  }

  /// O FCM troca o token sozinho (reinstalacao, restauracao de backup, limpeza
  /// de dados). Sem escutar isto, o aparelho para de receber em silencio.
  Stream<String> get onTokenRefresh =>
      _messaging?.onTokenRefresh ?? const Stream<String>.empty();

  /// O navegador bloqueou o aviso (a pessoa negou, ou desligou nas
  /// configuracoes do site). So a propria pessoa desfaz, pelo navegador.
  bool get isBlockedByBrowser => kIsWeb && WebBridge.pushPermission == 'denied';

  void _addTapJson(String json) {
    final tap = _tapFromJson(json);
    if (tap != null) _taps.add(tap);
  }

  static PushTap? _tapFromJson(String json) {
    try {
      final data = jsonDecode(json);
      return data is Map<String, dynamic> ? PushTap.fromData(data) : null;
    } catch (_) {
      return null;
    }
  }

  static bool _granted(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  Future<void> _showWhileOpen(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _plugin.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(FlutterLocalNotificationsPlugin());
});
