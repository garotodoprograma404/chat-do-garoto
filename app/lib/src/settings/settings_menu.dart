import 'package:flutter/material.dart';

/// The ⋮ menu of the app's sections, as in WhatsApp.
class SettingsMenuButton extends StatelessWidget {
  const SettingsMenuButton({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Mais opções',
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: onOpenSettings,
          child: const Text('Configurações'),
        ),
      ],
    );
  }
}
