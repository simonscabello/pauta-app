/// Configuracao injetada em tempo de build:
///   flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3000
///
/// Padrao 10.0.2.2 = o "localhost do Windows" visto de dentro do emulador
/// Android. Em celular fisico use o IP da maquina na rede local e libere a
/// porta 3000 no Firewall do Windows.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// O build da Google Play (`--dart-define=DISTRIBUTION=play`). App da loja
  /// não pode mandar baixar APK (política de Abuso de Dispositivo e Rede): a
  /// Play atualiza sozinha, e o aviso de versão nova some.
  static const bool isPlayStore =
      String.fromEnvironment('DISTRIBUTION') == 'play';

  /// Prefixo das rotas de negocio. /health fica fora dele.
  static const String apiUrl = '$apiBaseUrl/api/v1';

  /// O servidor MCP, que os assistentes de IA chamam com a chave da pessoa.
  /// Fora do `/api/v1`, como no backend: o protocolo tem versao propria, e
  /// `host/mcp` e o endereco que todo cliente espera.
  static const String mcpUrl = '$apiBaseUrl/mcp';

  /// O site (a versao Web), onde moram as paginas publicas: politica de
  /// privacidade, termos de uso e o pedido de exclusao da conta. Sao HTML
  /// estatico em `web/`, servidos pelo Caddy antes da SPA.
  ///
  /// Com padrao, ao contrario da API: estas paginas sao sempre as de
  /// producao, porque o texto que vale e o publicado -- e um APK de teste
  /// apontando para localhost mostraria uma pagina que nao existe.
  static const String siteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://app.pautalouvor.com.br',
  );

  static const String privacyUrl = '$siteUrl/privacidade.html';
  static const String termsUrl = '$siteUrl/termos.html';
  static const String accountDeletionUrl = '$siteUrl/excluir-conta.html';

  /// O site de apresentação, onde moram os guias. **Outro endereço** que o
  /// [siteUrl] (que, apesar do nome, é o do app, onde ficam as páginas legais).
  static const String publicSiteUrl = 'https://pautalouvor.com.br';

  /// O passo a passo de quem lidera, aberto pelo fim do tour do líder e pela
  /// Ajuda. Descreve o app de hoje: mudou um fluxo, muda o guia junto.
  static const String leaderGuideUrl = '$publicSiteUrl/guia/lider.html';

  /// O guia curto de quem é integrante.
  static const String memberGuideUrl = '$publicSiteUrl/guia/integrante.html';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
