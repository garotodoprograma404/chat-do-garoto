import 'package:flutter/material.dart';

import '../demo/demo_app.dart';
import '../theme/brand_mark.dart';
import '../theme/responsive.dart';

/// How the screens are shown.
enum IntroMode {
  /// A new install, before the PIN: the backup warning must be confirmed,
  /// and a backup can be chosen to restore.
  newInstall,

  /// Already in use: once after updating, with the confirmation.
  existing,

  /// From Configurações → Privacidade e segurança: just reading.
  read,
}

/// What the app protects, what it does not, and the backup: three
/// short pages, before the PIN.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.mode, this.onDone});

  final IntroMode mode;

  /// Called when finished (not in reading mode), with whether the user has
  /// a backup to restore.
  final void Function({required bool restore})? onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _understood = false;
  bool _restore = false;

  bool get _reading => widget.mode == IntroMode.read;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) {
    setState(() => _page = page);
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _next() {
    if (_page < 2) return _go(_page + 1);
    if (_reading) {
      Navigator.of(context).maybePop();
      return;
    }
    widget.onDone?.call(restore: _restore);
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == 2;
    final canGo = !last || _reading || _understood;
    return Scaffold(
      appBar: _reading
          ? AppBar(title: const Text('Privacidade e segurança'))
          : null,
      body: DotGrid(
        child: ContentWidth(
          maxWidth: formWidth,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _Page(
                        first: true,
                        demo: !_reading,
                        title: 'O que o app protege',
                        points: const [
                          'Seus clientes, vendas e conversas ficam guardados só '
                              'neste celular, embaralhados (cifrados). Não existe '
                              'servidor nosso.',
                          'O app tem PIN e digital próprios e se tranca sozinho '
                              'quando você sai ou fica um tempo sem usar.',
                          'O que você apaga no app some de verdade.',
                          'Nem nós conseguimos ver os seus dados.',
                        ],
                      ),
                      const _Page(
                        title: 'O que o app não protege',
                        points: [
                          'O WhatsApp continua sabendo com quem você conversa e '
                              'quando, mas não o que vocês dizem.',
                          'As conversas continuam também no WhatsApp do seu '
                              'celular principal e nos backups dele. A outra '
                              'pessoa fica com a cópia dela.',
                          'Com o celular desbloqueado e o app aberto, quem '
                              'estiver com ele na mão vê tudo.',
                          'Abra o WhatsApp do celular principal ao menos uma vez '
                              'a cada 14 dias, ou o app é desconectado.',
                          // The one connection besides WhatsApp.
                          'Ao tocar em "Buscar CEP", só o número do CEP vai para '
                              'um serviço público de CEP (ViaCEP ou BrasilAPI).',
                        ],
                      ),
                      _Page(
                        title: 'Faça backup',
                        points: const [
                          'Os seus dados existem só neste celular. Sem backup, '
                              'se você perder o celular, ele for roubado ou você '
                              'esquecer o PIN e não puder usar a digital, tudo se '
                              'perde, e ninguém consegue recuperar, nem nós.',
                          'O backup é um arquivo protegido por uma senha só sua, '
                              'que você guarda fora do celular. O app vai lembrar '
                              'de fazer.',
                        ],
                        extra: _reading
                            ? null
                            : Column(
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: _understood,
                                    onChanged: (v) => setState(
                                      () => _understood = v ?? false,
                                    ),
                                    title: const Text(
                                      'Entendi que, sem backup, perco os dados se '
                                      'perder o celular ou esquecer o PIN',
                                    ),
                                  ),
                                  if (widget.mode == IntroMode.newInstall)
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: _restore,
                                      onChanged: (v) =>
                                          setState(() => _restore = v ?? false),
                                      title: const Text(
                                        'Tenho um backup para restaurar',
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_page > 0)
                        TextButton(
                          onPressed: () => _go(_page - 1),
                          child: const Text('Voltar'),
                        ),
                      const Spacer(),
                      Text('${_page + 1} de 3'),
                      const Spacer(),
                      FilledButton(
                        onPressed: canGo ? _next : null,
                        child: Text(last && _reading ? 'Fechar' : 'Continuar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.points,
    this.extra,
    this.first = false,
    this.demo = false,
  });

  final String title;
  final List<String> points;
  final Widget? extra;

  /// The first page opens with the Garoto's face and the app's name.
  final bool first;

  /// The first page also offers the demo.
  final bool demo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (first) ...[
          const Center(child: BrandLockup(size: 72, vertical: true)),
          if (demo) ...[
            const SizedBox(height: 16),
            const Center(child: DemoButton()),
          ],
          const SizedBox(height: 28),
        ],
        SemicolonText(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(p)),
              ],
            ),
          ),
        ?extra,
      ],
    );
  }
}
