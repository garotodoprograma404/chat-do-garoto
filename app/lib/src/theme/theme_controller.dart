import 'package:flutter/material.dart';

import '../storage/key_vault.dart';

/// Light, dark or the phone's choice. Kept in the system
/// vault: the PIN screen comes before app.db.
class ThemeController extends ChangeNotifier {
  ThemeController({required this.store});

  final KeyVault store;

  ThemeMode mode = ThemeMode.dark;

  /// Reads the choice; called before the first frame so nothing flickers.
  Future<void> load() async {
    mode = switch (await store.read()) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    notifyListeners();
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    await store.write(m.name);
  }
}

/// How each choice is called in Configurações → Aparência.
String themeModeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => 'Igual ao celular',
  ThemeMode.light => 'Claro',
  ThemeMode.dark => 'Escuro',
};

/// Asks which look to use and applies it at once.
Future<void> pickThemeMode(BuildContext context, ThemeController theme) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: theme,
          builder: (context, _) => RadioGroup<ThemeMode>(
            groupValue: theme.mode,
            onChanged: (m) {
              if (m == null) return;
              theme.set(m);
              Navigator.pop(context);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Aparência',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(themeModeLabel(m)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
