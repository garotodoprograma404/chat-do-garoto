import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../home/crm_scope.dart';
import '../intro/intro_screen.dart';
import '../lock/change_pin_screen.dart';
import '../lock/lock_controller.dart';
import '../platform/battery_screen.dart';
import '../theme/components.dart';
import '../theme/theme_controller.dart';
import '../whatsapp/connect_screen.dart';
import '../whatsapp/stability_screen.dart';
import '../whatsapp/whatsapp_controller.dart';
import 'quick_replies_screen.dart';

/// Configurações: the WhatsApp connection, its stability,
/// battery and security, in one place, in groups.
class SettingsScreen extends StatelessWidget {
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
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final prefs = CrmScope.maybeOf(context)?.chatPrefs;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListenableBuilder(
        listenable: Listenable.merge([whatsapp, lock, ?theme]),
        // In groups, each item with its icon.
        builder: (context, _) => ListView(
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
                ConnectScreen(
                  controller: whatsapp,
                  onOpenPrototype: onOpenPrototype,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Symbols.monitor_heart_rounded),
              title: const Text('Estabilidade da conexão'),
              onTap: () =>
                  _push(context, StabilityScreen(controller: whatsapp)),
            ),
            ListTile(
              leading: const Icon(Symbols.battery_charging_full_rounded),
              title: const Text('Bateria'),
              subtitle: const Text('Para a conexão não cair'),
              onTap: () =>
                  _push(context, BatteryScreen(keeper: whatsapp.keeper)),
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
              onTap: () =>
                  _push(context, const IntroScreen(mode: IntroMode.read)),
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
        ),
      ),
    );
  }
}
