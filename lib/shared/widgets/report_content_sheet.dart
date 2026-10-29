import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/responsive/adaptive_dialog.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_status_colors.dart';
import 'app_feedback.dart';
import 'app_notice.dart';
import 'app_submit_button.dart';

/// O que se denuncia: música do catálogo (o repertório de outra equipe) ou a
/// foto de alguém da equipe. Exigido pela política de conteúdo gerado por
/// usuário da Google Play; quem lê é o Pauta Admin.
enum ReportKind {
  catalogSong('CATALOG_SONG'),
  profilePhoto('PROFILE_PHOTO');

  const ReportKind(this.apiValue);
  final String apiValue;
}

/// Abre a folha de denúncia. [targetId] é o `sourceSongId` do catálogo ou o
/// id do vínculo de quem está na foto.
Future<void> showReportContentSheet(
  BuildContext context, {
  required ReportKind kind,
  required String targetId,
  required String subject,
}) async {
  final sent = await showAdaptiveSheet<bool>(
    context: context,
    maxWidth: 480,
    builder: (_) =>
        _ReportSheet(kind: kind, targetId: targetId, subject: subject),
  );
  if (sent == true && context.mounted) {
    showAppSnackBar(
      context,
      'Denúncia enviada. A equipe do Pauta vai analisar.',
      tone: AppTone.success,
    );
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.kind,
    required this.targetId,
    required this.subject,
  });

  final ReportKind kind;
  final String targetId;
  final String subject;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _reason = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final reason = _reason.text.trim();
      await ref.read(dioProvider).post<void>(
        '/content-reports',
        data: {
          'kind': widget.kind.apiValue,
          'targetId': widget.targetId,
          if (reason.isNotEmpty) 'reason': reason,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.kind == ReportKind.catalogSong
                  ? 'Denunciar música'
                  : 'Denunciar foto',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.subject,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'O que há de errado? (opcional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppNotice(
                tone: AppTone.danger,
                message: _error!,
                liveRegion: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppSubmitButton(
              label: 'Enviar denúncia',
              loadingLabel: 'Enviando',
              loading: _sending,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}
