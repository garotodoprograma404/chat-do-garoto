import 'package:flutter/material.dart';

import '../theme/responsive.dart';

/// The ⋮ menu of the app's sections, as in WhatsApp.
class SettingsMenuButton extends StatelessWidget {
  const SettingsMenuButton({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // The side bar has its own gear: no second way to the same place.
    if (windowClass(context) != WindowClass.compact) {
      return const SizedBox.shrink();
    }
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
