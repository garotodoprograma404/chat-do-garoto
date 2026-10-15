import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chats/chat_prefs.dart';
import '../home/crm_scope.dart';
import '../intro/intro_screen.dart';
import '../lock/change_pin_screen.dart';
import '../lock/lock_controller.dart';
import '../platform/battery_screen.dart';
import '../theme/brand_mark.dart';
import '../theme/components.dart';
import '../theme/responsive.dart';
import '../theme/status_colors.dart';
import '../theme/theme_controller.dart';
import '../whatsapp/connect_screen.dart';
import '../whatsapp/stability_screen.dart';
import '../whatsapp/whatsapp_controller.dart';
import 'quick_replies_screen.dart';

/// Configurações: the WhatsApp connection, its stability,
/// battery and security, in one place, in groups.
class SettingsScreen extends StatelessWidget implements WideScreen {
  const SettingsScreen({
    super.key,
    required this.whatsapp,
    required this.lock,
    this.onOpenPrototype,
    this.onOpenBackup,
    this.theme,
  });

  /// Light, dark or the phone's choice; hidden when null.
  final ThemeController? theme;

  final WhatsAppController whatsapp;
  final LockController lock;

  /// Opens the phase 1 test screen; hidden when null.
  final VoidCallback? onOpenPrototype;

  /// Opens Backup; hidden when null.
  final VoidCallback? onOpenBackup;

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(appRoute<void>(screen));

  /// The same settings as a panel of cards, for a wide window:
  /// one card per group, the controls in sight (the theme is chosen right
  /// there), the connection's situation as a pill.
  Widget _wide(BuildContext context, ChatPrefs? prefs) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) => AppListTile(
      leading: Icon(icon, color: c.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Symbols.chevron_right_rounded, color: c.onSurfaceVariant)),
      onTap: onTap,
    );
    final connection = switch (whatsapp.phase) {
      WhatsAppPhase.connected => const StatusPill('Conectado', Situation.ok),
      WhatsAppPhase.pairing => const StatusPill('Desconectado', Situation.off),
      _ => const StatusPill('Conectando…', Situation.open),
    };
    final left = <Widget>[
      AppCard(
        title: 'WhatsApp',
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            row(
              icon: Symbols.link_rounded,
              title: 'Conexão com o WhatsApp',
              subtitle: 'Ligar, desligar ou refazer o pareamento',
              trailing: connection,
              onTap: () => _push(
                context,
                ConnectScreen(
                  controller: whatsapp,
                  onOpenPrototype: onOpenPrototype,
                ),
              ),
            ),
            row(
              icon: Symbols.monitor_heart_rounded,
              title: 'Estabilidade da conexão',
              subtitle: 'Quedas e tempo conectado',
              onTap: () =>
                  _push(context, StabilityScreen(controller: whatsapp)),
            ),
            row(
              icon: Symbols.battery_charging_full_rounded,
              title: 'Bateria',
              subtitle: 'Para a conexão não cair',
              onTap: () =>
                  _push(context, BatteryScreen(keeper: whatsapp.keeper)),
            ),
          ],
        ),
      ),
      if (prefs != null)
        AppCard(
          title: 'Conversas',
          padding: const EdgeInsets.only(bottom: 8),
          child: row(
            icon: Symbols.quickreply_rounded,
            title: 'Respostas rápidas',
            subtitle: 'Textos prontos, com / na conversa',
            onTap: () => _push(context, QuickRepliesScreen(prefs: prefs)),
          ),
        ),
      if (onOpenBackup case final open?)
        AppCard(
          title: 'Dados',
          padding: const EdgeInsets.only(bottom: 8),
          child: row(
            icon: Symbols.backup_rounded,
            title: 'Backup',
            subtitle: 'Fazer, restaurar e lembrete',
            onTap: open,
          ),
        ),
    ];
    final right = <Widget>[
      if (theme case final themeController?)
        AppCard(
          title: 'Aparência',
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                'Como o app aparece neste aparelho.',
                style: t.bodyMedium!.copyWith(color: c.onSurfaceVariant),
              ),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  for (final m in ThemeMode.values)
                    ButtonSegment(value: m, label: Text(themeModeLabel(m))),
                ],
                selected: {themeController.mode},
                onSelectionChanged: (s) => themeController.set(s.first),
              ),
            ],
          ),
        ),
      AppCard(
        title: 'Segurança',
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            row(
              icon: Symbols.shield_lock_rounded,
              title: 'Privacidade e segurança',
              subtitle: 'O que o app protege e o que não protege',
              onTap: () =>
                  _push(context, const IntroScreen(mode: IntroMode.read)),
            ),
            row(
              icon: Symbols.pin_rounded,
              title: 'Trocar PIN',
              onTap: () => _push(context, ChangePinScreen(controller: lock)),
            ),
            if (lock.biometricsAvailable)
              SwitchListTile(
                secondary: Icon(Symbols.fingerprint_rounded, color: c.primary),
                title: const Text('Desbloquear com a digital'),
                value: lock.biometricsOn,
                onChanged: (on) =>
                    on ? lock.enableBiometrics() : lock.disableBiometrics(),
              ),
          ],
        ),
      ),
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const BrandMark(size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SemicolonText('Chat do Garoto', style: t.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Sistema grátis do canal Garoto do Programa. Código '
                    'aberto (GPL-3.0). Seus dados ficam só neste aparelho.',
                    style: t.bodyMedium!.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Expanded(child: Column(spacing: 16, children: left)),
          Expanded(child: Column(spacing: 16, children: right)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = CrmScope.maybeOf(context)?.chatPrefs;
    return Scaffold(
      appBar: AppBar(title: const SemicolonText('Configurações')),
      body: ListenableBuilder(
        listenable: Listenable.merge([whatsapp, lock, ?theme]),
        // In groups, each item with its icon.
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 900
              ? _wide(context, prefs)
              : _narrow(context, prefs),
        ),
      ),
    );
  }

  /// The list of a phone or a narrow window.
  Widget _narrow(BuildContext context, ChatPrefs? prefs) => ListView(
    padding: EdgeInsets.only(bottom: listBottomPadding(context)),
    children: [
      const SectionHeader('WhatsApp'),
      ListTile(
        leading: const Icon(Symbols.link_rounded),
        title: const Text('Conexão com o WhatsApp'),
        subtitle: Text(switch (whatsapp.phase) {
          WhatsAppPhase.connected => 'Conectado',
          WhatsAppPhase.pairing => 'Desconectado',
          _ => 'Conectando…',
        }),
        onTap: () => _push(
          context,
          ConnectScreen(controller: whatsapp, onOpenPrototype: onOpenPrototype),
        ),
      ),
      ListTile(
        leading: const Icon(Symbols.monitor_heart_rounded),
        title: const Text('Estabilidade da conexão'),
        onTap: () => _push(context, StabilityScreen(controller: whatsapp)),
      ),
      ListTile(
        leading: const Icon(Symbols.battery_charging_full_rounded),
        title: const Text('Bateria'),
        subtitle: const Text('Para a conexão não cair'),
        onTap: () => _push(context, BatteryScreen(keeper: whatsapp.keeper)),
      ),
      if (prefs != null) ...[
        const SectionHeader('Conversas'),
        ListTile(
          leading: const Icon(Symbols.quickreply_rounded),
          title: const Text('Respostas rápidas'),
          subtitle: const Text('Textos prontos, com / na conversa'),
          onTap: () => _push(context, QuickRepliesScreen(prefs: prefs)),
        ),
      ],
      if (onOpenBackup case final open?) ...[
        const SectionHeader('Dados'),
        ListTile(
          leading: const Icon(Symbols.backup_rounded),
          title: const Text('Backup'),
          subtitle: const Text('Fazer, restaurar e lembrete'),
          onTap: open,
        ),
      ],
      if (theme case final t?) ...[
        const SectionHeader('Aparência'),
        ListTile(
          leading: const Icon(Symbols.contrast_rounded),
          title: const Text('Tema'),
          subtitle: Text(themeModeLabel(t.mode)),
          onTap: () => pickThemeMode(context, t),
        ),
      ],
      const SectionHeader('Segurança'),
      ListTile(
        leading: const Icon(Symbols.shield_lock_rounded),
        title: const Text('Privacidade e segurança'),
        subtitle: const Text('O que o app protege e o que não protege'),
        onTap: () => _push(context, const IntroScreen(mode: IntroMode.read)),
      ),
      ListTile(
        leading: const Icon(Symbols.pin_rounded),
        title: const Text('Trocar PIN'),
        onTap: () => _push(context, ChangePinScreen(controller: lock)),
      ),
      if (lock.biometricsAvailable)
        SwitchListTile(
          secondary: const Icon(Symbols.fingerprint_rounded),
          title: const Text('Desbloquear com a digital'),
          value: lock.biometricsOn,
          onChanged: (on) =>
              on ? lock.enableBiometrics() : lock.disableBiometrics(),
        ),
    ],
  );
}
