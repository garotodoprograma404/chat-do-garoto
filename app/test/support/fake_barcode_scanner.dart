import 'package:chat_do_garoto/src/scan/barcode_scanner.dart';
import 'package:flutter/widgets.dart';

/// A [BarcodeScanner] that "reads" the codes it was given.
class FakeBarcodeScanner implements BarcodeScanner {
  /// What [scanOne] reads, in order; empty is like closing the camera.
  final one = <String>[];

  /// What [scanMany] reads, one after another.
  List<String> many = [];

  /// What [scanMany] told the user for each code.
  final messages = <String>[];

  @override
  Future<String?> scanOne(BuildContext context) async =>
      one.isEmpty ? null : one.removeAt(0);

  @override
  Future<void> scanMany(
    BuildContext context, {
    required Future<String> Function(String code) onCode,
  }) async {
    for (final code in many) {
      messages.add(await onCode(code));
    }
  }
}
