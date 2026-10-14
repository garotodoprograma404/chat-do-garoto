import 'package:flutter/foundation.dart';

import '../storage/key_vault.dart';

/// Whether the first-run screens were seen. The mark lives in
/// the system vault: app.db only opens after the PIN.
class IntroController extends ChangeNotifier {
  IntroController({required this.store});

  final KeyVault store;

  /// Null while reading.
  bool? seen;

  /// The user said there is a backup to restore (new install); the app
  /// opens "Restaurar backup" right after the PIN.
  bool restoreWanted = false;

  Future<void> start() async {
    seen = await store.read() == '1';
    notifyListeners();
  }

  /// The screens were read and the backup warning confirmed.
  Future<void> complete({bool restore = false}) async {
    await store.write('1');
    seen = true;
    restoreWanted = restore;
    notifyListeners();
  }

  /// "Restaurar backup" was opened once.
  void restoreOffered() => restoreWanted = false;
}
