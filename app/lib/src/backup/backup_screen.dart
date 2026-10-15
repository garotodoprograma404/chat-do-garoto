import 'package:flutter/material.dart';

import '../chats/media/media_tiles.dart' show formatSize;
import 'backup_controller.dart';

/// Configurações → Backup: make one, restore one, the last date
/// and the reminder.
class BackupScreen extends StatelessWidget {
  const BackupScreen({
    super.key,
    required this.controller,
    this.mediaBytes,
    this.canExport = true,
  });

  final BackupController controller;

  /// Size of the media, shown next to "Incluir mídias".
  final Future<int> Function()? mediaBytes;

  /// False where only restoring makes sense (app.db could not be opened).
  final bool canExport;

  Future<void> _export(BuildContext context) async {
    final bytes = await mediaBytes?.call();
    if (!context.mounted) return;
    final choice = await showDialog<({String password, bool media})>(
      context: context,
      builder: (_) => _ExportDialog(mediaBytes: bytes),
    );
    if (choice == null) return;
    await controller.export(password: choice.password, media: choice.media);
  }

  Future<void> _restore(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _RestoreDialog(),
    );
    if (password == null) return;
    await controller.restore(password: password);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Text(switch (c.lastBackup) {
                null => 'Você ainda não fez backup.',
                final d =>
                  'Último backup: ${_two(d.day)}/${_two(d.month)}/${d.year}',
              }),
              const SizedBox(height: 8),
              const Text(
                'O backup é um arquivo cifrado com uma senha só sua. Guarde-o '
                'fora do celular (Drive, pendrive, e-mail) para recuperar os '
                'dados se perder o aparelho.',
              ),
              const SizedBox(height: 16),
              if (canExport)
                FilledButton(
                  onPressed: c.busy ? null : () => _export(context),
                  child: const Text('Fazer backup agora'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: c.busy ? null : () => _restore(context),
                child: const Text('Restaurar backup'),
              ),
              const SizedBox(height: 16),
              _Status(controller: c),
              if (canExport) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Text('Lembrar de fazer backup')),
                    DropdownButton<int>(
                      value: c.intervalDays,
                      items: [
                        for (final d in reminderChoices)
                          DropdownMenuItem(
                            value: d,
                            child: Text(
                              d == 0 ? 'Desligado' : 'A cada $d dias',
                            ),
                          ),
                      ],
                      onChanged: (d) => d == null ? null : c.setInterval(d),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

class _Status extends StatelessWidget {
  const _Status({required this.controller});

  final BackupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return switch (c.phase) {
      BackupPhase.idle => const SizedBox.shrink(),
      BackupPhase.exporting => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.total == 0
                ? 'Preparando o backup…'
                : 'Gravando o backup: ${formatSize(c.done)} de ${formatSize(c.total)}',
          ),
          LinearProgressIndicator(
            value: c.total == 0 ? null : c.done / c.total,
          ),
          TextButton(onPressed: c.cancel, child: const Text('Cancelar')),
        ],
      ),
      BackupPhase.opening => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conferindo o backup…'),
          const LinearProgressIndicator(),
          TextButton(onPressed: c.cancel, child: const Text('Cancelar')),
        ],
      ),
      BackupPhase.restoring => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('Restaurando…'), LinearProgressIndicator()],
      ),
      BackupPhase.done => _Result('Backup concluído.', onOk: c.dismiss),
      BackupPhase.restored => _Result('Backup restaurado.', onOk: c.dismiss),
      BackupPhase.failed => _Result(
        c.error ?? 'Algo deu errado.',
        onOk: c.dismiss,
      ),
    };
  }
}

class _Result extends StatelessWidget {
  const _Result(this.text, {required this.onOk});

  final String text;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(text)),
      TextButton(onPressed: onOk, child: const Text('Fechar')),
    ],
  );
}

/// The password, twice, and whether the media go.
class _ExportDialog extends StatefulWidget {
  const _ExportDialog({this.mediaBytes});

  final int? mediaBytes;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _media = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  void _ok() {
    final p = _password.text;
    setState(() {
      _error = p.length < minBackupPassword
          ? 'Use ao menos $minBackupPassword caracteres.'
          : p != _again.text
          ? 'As senhas não são iguais.'
          : null;
    });
    if (_error == null) Navigator.pop(context, (password: p, media: _media));
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.mediaBytes;
    return AlertDialog(
      title: const Text('Fazer backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          // 16 between the fields of a dialog.
          spacing: 16,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha do backup'),
            ),
            TextField(
              controller: _again,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Repita a senha',
                errorText: _error,
              ),
            ),
            const Text(
              'Sem esta senha ninguém abre o backup, nem nós. Guarde-a num '
              'lugar seguro.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _media,
              onChanged: (v) => setState(() => _media = v ?? true),
              title: Text(
                'Incluir mídias (fotos, áudios, vídeos e documentos das '
                'conversas)${size == null ? '' : ' · ${formatSize(size)}'}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _ok, child: const Text('Continuar')),
      ],
    );
  }
}

/// The warning and the password, before picking the file.
class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog();

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restaurar backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          const Text(
            'Restaurar substitui todos os dados do app neste aparelho '
            '(clientes, produtos, vendas, conversas e mídias) pelos do backup.',
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha do backup'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => _password.text.isEmpty
              ? null
              : Navigator.pop(context, _password.text),
          child: const Text('Escolher o arquivo'),
        ),
      ],
    );
  }
}

/// The reminder at the top of the app.
class BackupReminder extends StatelessWidget {
  const BackupReminder({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final BackupController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.reminderDue || controller.busy) {
        return const SizedBox.shrink();
      }
      final days = controller.daysSinceBackup;
      return Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    days == null
                        ? 'Você ainda não fez backup.'
                        : 'Seu último backup foi há $days dias.',
                  ),
                ),
                TextButton(onPressed: onOpen, child: const Text('Fazer agora')),
              ],
            ),
          ),
        ),
      );
    },
  );
}
