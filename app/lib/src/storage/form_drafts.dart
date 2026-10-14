import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_database.dart';

/// What was typed in a form not saved yet, by form name.
abstract interface class FormDrafts {
  /// The fields of [form]'s draft, or null when there is none.
  Future<Map<String, String>?> read(String form);
  Future<void> write(String form, Map<String, String> fields);
  Future<void> clear(String form);
}

/// [FormDrafts] in app.db's preferences table, as JSON: encrypted with the
/// rest of app.db, and overwritten with nothing when cleared.
class DriftFormDrafts implements FormDrafts {
  DriftFormDrafts(this._db);

  final AppDatabase _db;

  String _name(String form) => 'draft_$form';

  @override
  Future<Map<String, String>?> read(String form) async {
    final raw = await _db.preference(_name(form));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = (jsonDecode(raw) as Map<String, Object?>).map(
        (k, v) => MapEntry(k, v as String? ?? ''),
      );
      return map.values.any((v) => v.trim().isNotEmpty) ? map : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String form, Map<String, String> fields) =>
      _db.setPreference(_name(form), jsonEncode(fields));

  @override
  Future<void> clear(String form) => _db.setPreference(_name(form), '');
}

/// Keeps the draft of a new form while it is typed: every
/// change is written half a second later, and whatever is left when the
/// screen closes without saving.
class DraftKeeper {
  DraftKeeper({
    required this.form,
    required this.drafts,
    required this.fields,
    this.enabled = true,
  });

  final String form;

  /// Set when the screen finds app.db (`CrmScope.drafts`).
  FormDrafts? drafts;
  final Map<String, TextEditingController> fields;

  /// False for forms that are not drafted (editing, coming from a chat).
  bool enabled;

  /// Something was typed since the screen opened.
  bool dirty = false;

  Timer? _timer;
  VoidCallback? _onDirty;

  void start(VoidCallback onDirty) {
    _onDirty = onDirty;
    for (final c in fields.values) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (!dirty) {
      dirty = true;
      _onDirty?.call();
    }
    if (!enabled || drafts == null) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), save);
  }

  Future<void> save() async {
    if (!enabled) return;
    await drafts?.write(form, {
      for (final MapEntry(:key, :value) in fields.entries) key: value.text,
    });
  }

  /// The draft left from before, if any.
  Future<Map<String, String>?> pending() async =>
      enabled ? await drafts?.read(form) : null;

  void restore(Map<String, String> values) {
    for (final MapEntry(:key, :value) in values.entries) {
      fields[key]?.text = value;
    }
  }

  /// Saved or discarded: no draft any more.
  Future<void> clear() async {
    _timer?.cancel();
    final was = enabled;
    enabled = false;
    if (was) await drafts?.clear(form);
  }

  void dispose() {
    _timer?.cancel();
    if (dirty && enabled) unawaited(save());
  }
}

/// "Continuar o cadastro de onde parou?": true to continue.
Future<bool> askContinueDraft(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continuar de onde parou?'),
        content: const Text(
          'Há um cadastro começado e não salvo. Continuar com o que já foi '
          'digitado?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    ) ??
    false;

/// "Descartar o cadastro?": true to leave without saving.
Future<bool> confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar o que foi digitado?'),
        content: const Text('O que não foi salvo será perdido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    ) ??
    false;
