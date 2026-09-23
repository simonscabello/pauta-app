import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/open_link.dart';

/// Um recurso para ensaiar: cifra, letra, YouTube, Spotify.
class SongResource {
  const SongResource({
    required this.icon,
    required this.label,
    required this.status,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// O que o toque faz ("Abrir cifra"), ou "Sem link".
  final String status;

  /// Nulo quando não há o que abrir.
  final VoidCallback? onTap;
}

/// Os ícones dos recursos, os mesmos em toda tela: a linha do repertório, a
/// folha da música na escala, a sugestão e a tela da música.
abstract final class SongResourceIcons {
  static const chords = Icons.music_note_rounded;
  static const lyrics = Icons.article_outlined;
  static const youtube = Icons.play_circle_outline_rounded;
  static const spotify = Icons.headphones_rounded;
}

bool _filled(String? value) => value != null && value.trim().isNotEmpty;


/// Os quatro recursos de uma música, **sempre os quatro e na mesma ordem**.
///
/// Esconder o que falta faria a grade mudar de forma de uma música para outra,
/// e "esta música está sem cifra" é justamente o que a equipe precisa ver para
/// ir atrás dela. [onOpenLyrics] abre a letra guardada; sem ele, vale o link.
List<SongResource> songResources(
  BuildContext context, {
  required String? chordsUrl,
  required String? lyricsUrl,
  required String? youtubeUrl,
  required String? spotifyUrl,
  VoidCallback? onOpenLyrics,
}) {
  SongResource link(IconData icon, String label, String? url, String action) =>
      SongResource(
        icon: icon,
        label: label,
        status: _filled(url) ? action : 'Sem link',
        onTap: _filled(url) ? () => openExternalLink(context, url!) : null,
      );

  return [
    link(SongResourceIcons.chords, 'Cifra', chordsUrl, 'Abrir cifra'),
    onOpenLyrics != null
        ? SongResource(
            icon: SongResourceIcons.lyrics,
            label: 'Letra',
            status: 'Ler no app',
            onTap: onOpenLyrics,
          )
        : link(SongResourceIcons.lyrics, 'Letra', lyricsUrl, 'Abrir no site'),
    link(SongResourceIcons.youtube, 'YouTube', youtubeUrl, 'Ver no YouTube'),
    link(SongResourceIcons.spotify, 'Spotify', spotifyUrl, 'Ouvir no Spotify'),
  ];
}

/// Os recursos em grade de duas colunas, com o que o toque faz escrito
/// embaixo. É a versão da tela da música, onde há espaço.
class SongResourceGrid extends StatelessWidget {
  const SongResourceGrid({super.key, required this.resources});

  final List<SongResource> resources;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < resources.length; row += 2) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          // Altura igual nas duas colunas: com a fonte do sistema aumentada,
          // um rótulo quebra e o vizinho ficaria mais baixo.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _GridTile(resource: resources[row])),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: row + 1 < resources.length
                      ? _GridTile(resource: resources[row + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.resource});

  final SongResource resource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = resource.onTap != null;
    final muted = scheme.onSurfaceVariant;

    return AppCard(
      onTap: resource.onTap,
      // Sem nada para abrir, o ladrilho afunda na página: sem borda e sem
      // seta, lê-se como vaga, não como botão que não responde.
      surface: available ? CardSurface.plain : CardSurface.sunken,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                resource.icon,
                size: 22,
                color: available ? scheme.primary : muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  resource.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: available ? scheme.onSurface : muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  resource.status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              if (available)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: muted.withValues(alpha: 0.7),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Os recursos numa linha só: a versão compacta, para folhas e cabeçalhos onde
/// a grade gastaria meia tela.
///
/// Mesmos ícones, mesma ordem e o mesmo estado apagado da grade — muda só a
/// arrumação. O que o toque faz vai para o leitor de tela, que não vê o ícone.
class SongResourceRow extends StatelessWidget {
  const SongResourceRow({super.key, required this.resources});

  final List<SongResource> resources;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < resources.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: _RowTile(resource: resources[i])),
          ],
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.resource});

  final SongResource resource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = resource.onTap != null;
    final muted = scheme.onSurfaceVariant;

    return Semantics(
      button: available,
      label: '${resource.label}: ${resource.status}',
      excludeSemantics: true,
      child: AppCard(
        onTap: resource.onTap,
        surface: available ? CardSurface.plain : CardSurface.sunken,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              resource.icon,
              size: 22,
              color: available ? scheme.primary : muted,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              resource.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: available ? scheme.onSurface : muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!available)
              Text(
                'Sem link',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
