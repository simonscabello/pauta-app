import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../auth/application/auth_controller.dart';

/// Abre a câmera ou a galeria já com os limites do envio. Nulo quando a
/// pessoa desistiu. É o mesmo caminho da foto do Perfil e do "Complete seu
/// perfil" do tour.
Future<XFile?> pickAvatarImage(ImageSource source) {
  return ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
}

/// Envia a imagem escolhida como foto de perfil.
///
/// Bytes, e nao `picked.path`: no navegador o caminho e uma URL `blob:` e
/// `dart:io` nao existe para abri-la. `readAsBytes` e a unica leitura que o
/// `XFile` oferece nas duas plataformas.
Future<void> uploadAvatarImage(WidgetRef ref, XFile picked) async {
  final bytes = await picked.readAsBytes();
  await ref.read(authControllerProvider.notifier).updateAvatar(
        bytes: bytes,
        filename: picked.name,
      );
}

/// Foto de perfil com o gesto de troca embutido.
///
/// O arquivo sai do celular ja reduzido (1024px, qualidade 85): uma foto de
/// camera moderna passa de 5 MB, que e o limite do backend, e a diferenca nao
/// aparece num circulo de 72px. O `imageQuality` tambem reencoda em JPEG, o
/// que resolve o HEIC dos aparelhos mais novos.
class ProfilePhoto extends ConsumerStatefulWidget {
  const ProfilePhoto({super.key, this.radius = 36});

  final double radius;

  @override
  ConsumerState<ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends ConsumerState<ProfilePhoto> {
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    final picked = await pickAvatarImage(source);
    if (picked == null) return;
    await _run(() => uploadAvatarImage(ref, picked), done: 'Foto atualizada.');
  }

  Future<void> _remove() {
    return _run(
      () => ref.read(authControllerProvider.notifier).removeAvatar(),
      done: 'Foto removida.',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String done,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        showAppSnackBar(context, done, tone: AppTone.success);
      }
    } on ApiException catch (error) {
      _warn(error.message);
    } catch (_) {
      // Galeria negada, arquivo ilegivel, plugin sem permissao: nada disso
      // vira ApiException e todos terminam do mesmo jeito para o usuario.
      _warn('Não foi possível usar esta imagem.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _warn(String message) {
    if (!mounted) return;
    showAppSnackBar(context, message, tone: AppTone.danger);
  }

  Future<void> _openOptions() async {
    final hasPhoto = ref.read(authControllerProvider).user?.avatarUrl != null;

    // Folha no celular, dialogo no monitor: sao tres linhas de escolha, e no
    // navegador elas apareceriam no rodape de uma janela de 1080px, longe do
    // avatar em que a pessoa acabou de clicar.
    final choice = await showAdaptiveSheet<_PhotoAction>(
      context: context,
      maxWidth: 420,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: const Text('Remover foto'),
                onTap: () => Navigator.pop(sheetContext, _PhotoAction.remove),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );

    switch (choice) {
      case _PhotoAction.camera:
        await _pick(ImageSource.camera);
      case _PhotoAction.gallery:
        await _pick(ImageSource.gallery);
      case _PhotoAction.remove:
        await _remove();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final scheme = Theme.of(context).colorScheme;

    if (user == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: 'Alterar foto de perfil',
      child: InkWell(
        onTap: _busy ? null : _openOptions,
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AppAvatar(
              name: user.name,
              // A URL muda a cada envio (o nome do arquivo e um UUID), entao
              // o cache do Image.network nunca entrega a foto antiga.
              imageUrl: user.avatarUrl,
              radius: widget.radius,
            ),
            if (_busy)
              CircleAvatar(
                radius: widget.radius,
                backgroundColor: scheme.scrim.withValues(alpha: 0.45),
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(
                  Icons.photo_camera_rounded,
                  size: 14,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoAction { camera, gallery, remove }
