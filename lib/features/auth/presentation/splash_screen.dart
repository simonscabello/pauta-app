import 'package:flutter/material.dart';

import 'splash_frame.dart';

/// Exibida enquanto o AuthController verifica se existe sessao salva.
/// O redirect do go_router tira o usuario daqui assim que o estado resolve.
///
/// É o primeiro frame do app, e por isso a única tela em que a marca aparece
/// grande. O indicador fica no mesmo bloco da marca, no centro da viewport —
/// um `Column` solto no `Scaffold` encolhe à largura do texto e encosta à
/// esquerda, que é o que fazia a abertura parecer desalinhada em tablet e no
/// navegador. O layout é o [SplashFrame], o mesmo do desbloqueio.
///
/// **Nada anima aqui além do indicador.** A abertura é o intervalo entre tocar
/// no ícone e ver a escala; qualquer coisa que precise de tempo para acontecer
/// só faz esse intervalo parecer maior.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SplashFrame(below: SplashProgress());
  }
}
