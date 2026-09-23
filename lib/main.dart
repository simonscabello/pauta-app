import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'core/platform/keyboard_back_guard.dart';
import 'core/push/push_coordinator.dart';
import 'core/router/app_router.dart';
import 'core/storage/shared_preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/onboarding/presentation/tour_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A árvore de acessibilidade ligada desde a abertura, na Web. O Flutter Web
  // só monta a semântica depois que alguém aciona um botão escondido, em
  // inglês ("Enable accessibility"): para o leitor de tela, a página inteira
  // era esse botão. O identificador fica sem `dispose` de propósito — a
  // árvore vale pela vida do app. No Android quem decide é o sistema.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  tzdata.initializeTimeZones();
  // Datas em portugues ("12 de agosto"). Sem isto o DateFormat com locale
  // pt_BR lanca excecao em tempo de execucao.
  await initializeDateFormatting('pt_BR');
  final prefs = await SharedPreferences.getInstance();
  // Antes do `runApp`, para ser consultado antes do roteador.
  KeyboardBackGuard.install();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const LouvorApp(),
    ),
  );
}

class LouvorApp extends ConsumerWidget {
  const LouvorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observado, e nao lido: e o que faz o coordenador existir durante a vida
    // do app. Ele mesmo escuta o estado de autenticacao -- registra o aparelho
    // ao entrar na conta e leva o toque no aviso ate a tela.
    ref.watch(pushCoordinatorProvider);

    return MaterialApp.router(
      title: 'Pauta',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      // O tour dos integrantes fica acima do Navigator: ele anda de tela em
      // tela, e uma camada que pertencesse a uma página sumiria com ela.
      builder: (context, child) =>
          OnboardingTourHost(child: child ?? const SizedBox.shrink()),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
