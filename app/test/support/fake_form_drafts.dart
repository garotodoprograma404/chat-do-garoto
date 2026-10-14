import 'package:chat_do_garoto/src/storage/form_drafts.dart';

/// In-memory [FormDrafts].
class FakeFormDrafts implements FormDrafts {
  final saved = <String, Map<String, String>>{};

  @override
  Future<Map<String, String>?> read(String form) async {
    final d = saved[form];
    return d == null || d.values.every((v) => v.trim().isEmpty) ? null : d;
  }

  @override
  Future<void> write(String form, Map<String, String> fields) async =>
      saved[form] = {...fields};

  @override
  Future<void> clear(String form) async => saved.remove(form);
}
