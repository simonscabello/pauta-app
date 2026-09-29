/// O grupo do WhatsApp da equipe, visto por quem lidera.
///
/// Espelha `GET /teams/:teamId/whatsapp`. O servidor decide tudo o que importa
/// aqui -- se a integração está ligada, se o número do Pauta está conectado e
/// qual grupo foi vinculado --; o app só desenha.
class TeamWhatsApp {
  const TeamWhatsApp({
    required this.available,
    required this.connected,
    this.phoneNumber,
    this.group,
    this.linkCode,
  });

  /// O servidor tem o envio pelo WhatsApp ligado. Falso: nada disto aparece
  /// no app, nem a linha em Gerenciar equipe nem o botão da escala.
  final bool available;

  /// O número do Pauta está conectado ao WhatsApp agora.
  final bool connected;

  /// Só dígitos, com o DDI (`5527999990000`).
  final String? phoneNumber;

  final WhatsAppGroup? group;
  final WhatsAppLinkCode? linkCode;

  /// O botão "Enviar para o grupo" da escala só existe com as duas coisas.
  bool get canSend => available && group != null;

  factory TeamWhatsApp.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>?;
    final code = json['linkCode'] as Map<String, dynamic>?;
    return TeamWhatsApp(
      available: json['available'] == true,
      connected: json['connected'] == true,
      phoneNumber: json['phoneNumber'] as String?,
      group: group == null
          ? null
          : WhatsAppGroup(
              name: group['name'] as String?,
              linkedAt: DateTime.parse(group['linkedAt'] as String).toLocal(),
            ),
      linkCode: code == null
          ? null
          : WhatsAppLinkCode(
              code: code['code'] as String,
              expiresAt: DateTime.parse(code['expiresAt'] as String).toLocal(),
            ),
    );
  }

  static const off = TeamWhatsApp(available: false, connected: false);
}

class WhatsAppGroup {
  const WhatsAppGroup({required this.name, required this.linkedAt});

  /// O nome do grupo quando foi vinculado. Pode faltar, se o WhatsApp não
  /// respondeu na hora.
  final String? name;
  final DateTime linkedAt;

  String get label => name ?? 'o grupo vinculado';
}

class WhatsAppLinkCode {
  const WhatsAppLinkCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

/// `5527999990000` → `+55 27 99999-0000`. Número de outro formato volta com
/// o `+` e sem máscara: melhor mostrar cru do que agrupar errado.
String formatWhatsAppNumber(String digits) {
  final brazil = RegExp(r'^55(\d{2})(\d{4,5})(\d{4})$').firstMatch(digits);
  if (brazil == null) return '+$digits';
  return '+55 ${brazil[1]} ${brazil[2]}-${brazil[3]}';
}
