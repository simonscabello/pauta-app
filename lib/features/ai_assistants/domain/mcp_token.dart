import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Chaves ativas por pessoa. Espelha `MAX_ACTIVE_MCP_TOKENS` do backend, que
/// recusa a 11ª com 409 `MCP_TOKEN_LIMIT`.
const maxActiveMcpTokens = 10;

/// Os prazos que a API aceita (`MCP_TOKEN_TTL_DAYS`), na ordem da barra.
const mcpTokenValidityOptions = [30, 90, 180, 365];

/// O padrão da API quando o prazo não vem no corpo.
const defaultMcpTokenValidityDays = 90;

/// A partir de quantos dias para vencer a linha troca "Vale até" pelo selo
/// âmbar: uma semana é o tempo de alguém chegar ao computador e criar outra.
const mcpTokenWarningDays = 7;

/// O aviso "Melhor fazer no computador" na tela de criar a chave.
///
/// **Aqui quem decide é a plataforma, e não a largura** — ao contrário do resto
/// do app. A pergunta não é "cabe?", é "dá para colar a chave num terminal
/// daqui?": a chave vai para o Claude Code, o Cursor ou o VS Code, e um tablet
/// com o app do Android continua sem terminal. Na Web a pessoa quase sempre já
/// está no computador.
const newMcpTokenSuggestsComputer = !kIsWeb;

/// Uma chave de assistente de IA, como `GET /users/me/mcp-tokens` devolve.
///
/// **O valor inteiro não mora aqui.** A lista só traz a dica
/// (`pauta_mcp_...k3Fq`); a chave aparece uma vez, na resposta da criação
/// ([CreatedMcpToken]), e vive só no estado da tela que a mostra.
class McpToken {
  const McpToken({
    required this.id,
    required this.name,
    required this.tokenHint,
    required this.createdAt,
    required this.expiresAt,
    this.lastUsedAt,
    this.expired = false,
  });

  factory McpToken.fromJson(Map<String, dynamic> json) {
    final lastUsedAt = json['lastUsedAt'] as String?;
    return McpToken(
      id: json['id'] as String,
      name: json['name'] as String,
      tokenHint: json['tokenHint'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      lastUsedAt: lastUsedAt == null ? null : DateTime.parse(lastUsedAt),
      expired: json['expired'] as bool? ?? false,
    );
  }

  final String id;
  final String name;

  /// `pauta_mcp_...k3Fq`: o bastante para reconhecer, nunca para usar.
  final String tokenHint;

  final DateTime createdAt;
  final DateTime expiresAt;

  /// Nulo: nenhum assistente usou a chave ainda.
  final DateTime? lastUsedAt;

  /// Como o servidor viu, na hora da resposta.
  final bool expired;

  /// Os últimos caracteres, que a pessoa confere contra o que colou.
  String get ending {
    final cut = tokenHint.lastIndexOf('...');
    if (cut >= 0) return tokenHint.substring(cut + 3);
    return tokenHint.length <= 4
        ? tokenHint
        : tokenHint.substring(tokenHint.length - 4);
  }

  /// Vencida pelo servidor **ou** pelo relógio: a lista aberta de um dia para
  /// o outro não pode seguir chamando de ativa uma chave que já venceu.
  bool isExpiredAt(DateTime now) => expired || !expiresAt.isAfter(now);
}

/// A resposta de `POST /users/me/mcp-tokens`: a chave da lista mais o valor
/// inteiro, que **só existe aqui** e não volta nunca mais.
///
/// Quem recebe guarda no estado da tela de resultado e em mais lugar nenhum:
/// nada de provider, cache, armazenamento ou log.
class CreatedMcpToken {
  const CreatedMcpToken({required this.token, required this.secret});

  factory CreatedMcpToken.fromJson(Map<String, dynamic> json) {
    return CreatedMcpToken(
      token: McpToken.fromJson(json),
      secret: json['token'] as String,
    );
  }

  final McpToken token;

  /// `pauta_mcp_` e 43 caracteres base64url.
  final String secret;
}

/// Em que pé a chave está — decide a segunda linha e o selo.
enum McpTokenState { active, expiring, expired }

McpTokenState mcpTokenState(McpToken token, DateTime now) {
  if (token.isExpiredAt(now)) return McpTokenState.expired;
  return mcpTokenDaysLeft(token, now) <= mcpTokenWarningDays
      ? McpTokenState.expiring
      : McpTokenState.active;
}

/// Dias de calendário até vencer, no relógio do aparelho: 0 é "vence hoje".
int mcpTokenDaysLeft(McpToken token, DateTime now) =>
    _calendarDays(from: now, to: token.expiresAt.toLocal());

/// As chaves que ainda valem — é o que conta para o limite.
int activeMcpTokenCount(Iterable<McpToken> tokens, DateTime now) =>
    tokens.where((t) => !t.isExpiredAt(now)).length;

/// As que valem primeiro, da mais nova para a mais antiga; as vencidas no fim,
/// a que venceu por último em cima. A API ordena só pela criação, e uma chave
/// de um ano criada em março ficaria abaixo de uma de 30 dias que já morreu.
List<McpToken> sortMcpTokens(Iterable<McpToken> tokens, DateTime now) {
  final active = tokens.where((t) => !t.isExpiredAt(now)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final expired = tokens.where((t) => t.isExpiredAt(now)).toList()
    ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
  return [...active, ...expired];
}

/// "25 de dezembro", com o ano só quando não é o deste ano.
String mcpDayLabel(DateTime date, DateTime now) {
  final local = date.toLocal();
  final pattern =
      local.year == now.year ? "d 'de' MMMM" : "d 'de' MMMM 'de' y";
  return DateFormat(pattern, 'pt_BR').format(local);
}

/// O que vem depois de "Termina em k3Fq · ": quando foi usada, ou quando
/// venceu.
String mcpUsageLabel(McpToken token, DateTime now) {
  if (token.isExpiredAt(now)) {
    return 'venceu em ${mcpDayLabel(token.expiresAt, now)}';
  }
  final lastUsedAt = token.lastUsedAt;
  if (lastUsedAt == null) return 'nunca usada';
  final days = _calendarDays(from: lastUsedAt.toLocal(), to: now);
  if (days <= 0) return 'usada hoje';
  if (days == 1) return 'usada ontem';
  return 'usada em ${mcpDayLabel(lastUsedAt, now)}';
}

String mcpValidUntilLabel(McpToken token, DateTime now) =>
    'Vale até ${mcpDayLabel(token.expiresAt, now)}';

/// O selo âmbar dos últimos dias.
String mcpExpiringLabel(int daysLeft) => switch (daysLeft) {
      <= 0 => 'Vence hoje',
      1 => 'Vence amanhã',
      _ => 'Vence em $daysLeft dias',
    };

/// "2 de 10 ativas", no cabeçalho da lista.
String mcpActiveCountLabel(int active) =>
    '$active de $maxActiveMcpTokens ativas';

/// O rótulo de cada prazo na barra de escolha.
String mcpValidityOptionLabel(int days) => switch (days) {
      180 => '6 meses',
      365 => '1 ano',
      _ => '$days dias',
    };

/// A linha embaixo da barra de prazos. **Sempre com o ano**: é uma data
/// escolhida agora para daqui a meses, e "25 de março" sozinho não diz de
/// qual março.
String mcpNewTokenUntilLabel(int days, DateTime now) {
  final until = now.add(Duration(days: days));
  final date = DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(until);
  return 'Vale até $date. Depois, é só criar outra.';
}

/// O cabeçalho que Cursor, VS Code e afins mandam em cada chamada ao `/mcp`.
String mcpAuthorizationHeader(String secret) => 'Authorization: Bearer $secret';

/// O cabeçalho encurtado para caber numa linha
/// (`Authorization: Bearer pauta_mcp_U9u6…k3Fq`). Quem copia leva o inteiro.
String mcpAuthorizationHeaderPreview(String secret) {
  const prefix = 'pauta_mcp_';
  if (!secret.startsWith(prefix) || secret.length < prefix.length + 12) {
    return mcpAuthorizationHeader(secret);
  }
  final head = secret.substring(0, prefix.length + 4);
  final tail = secret.substring(secret.length - 4);
  return 'Authorization: Bearer $head…$tail';
}

/// O comando do Claude Code, pronto para colar no terminal.
///
/// `pauta` é o nome com que o servidor aparece no Claude Code. A chave é
/// base64url — sem espaço, aspas nem cifrão —, então o comando passa inteiro
/// no Bash, no PowerShell e no cmd sem escapar nada.
String claudeCodeMcpCommand({required String url, required String secret}) =>
    'claude mcp add --transport http pauta $url '
    '--header "${mcpAuthorizationHeader(secret)}"';

/// Dias de calendário entre duas datas, pela data e não pelas horas: 23h da
/// véspera e 1h de hoje estão a um dia de distância. Em UTC para o horário de
/// verão não transformar um dia de 23 horas em zero dias.
int _calendarDays({required DateTime from, required DateTime to}) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
