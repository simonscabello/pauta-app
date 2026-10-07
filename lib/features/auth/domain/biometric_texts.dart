/// Todos os textos da biometria num lugar só: o pedido do sistema, o
/// desbloqueio, o convite depois do login e o Perfil. As telas e os testes
/// leem daqui.
abstract final class BiometricTexts {
  // Janela do sistema (AndroidAuthMessages).
  static const systemReason = 'Confirme sua identidade para entrar no Pauta';
  static const systemTitle = 'Pauta';
  static const systemHint = 'Confirme que é você';
  static const systemCancel = 'Cancelar';

  // Desbloqueio.
  static const unlockPrompt = 'Confirme que é você para continuar.';
  static const unlockButton = 'Entrar com biometria';
  static const usePassword = 'Usar e-mail e senha';
  static const unlockOffline =
      'Não foi possível conectar ao servidor. Tente de novo ou entre com e-mail e senha.';
  static const unlockLockedOut =
      'Muitas tentativas. Espere um pouco ou entre com e-mail e senha.';
  static const sessionExpired =
      'Sua sessão expirou. Entre com seu e-mail e senha.';

  // Convite depois do login por senha.
  static const offerTitle = 'Entrar mais rápido da próxima vez?';
  static const offerBody =
      'Use a biometria do seu aparelho para acessar o Pauta sem precisar digitar sua senha.';
  static const offerDecline = 'Agora não';
  static const offerAccept = 'Usar biometria';

  // Perfil.
  static const profileTitle = 'Entrar com biometria';
  static const profileSubtitle = 'Segurança deste aparelho';
  static const profileNotConfirmed =
      'Biometria não confirmada. Tente novamente.';
  static const profileLockedOut =
      'Muitas tentativas. Espere um pouco e tente de novo.';
}
