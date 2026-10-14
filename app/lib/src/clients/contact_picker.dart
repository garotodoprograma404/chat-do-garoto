import 'package:flutter/services.dart';

/// A contact picked from the phone's address book: name and number as the
/// address book has them.
typedef PickedContact = ({String name, String phone});

/// "Escolher da agenda".
abstract interface class ContactPicker {
  /// The contact picked, or null when cancelled.
  Future<PickedContact?> pick();
}

/// The system's contact picker (`ContactPickerChannel.kt`): Android hands
/// over only the number picked, so the app never reads the address book.
class ChannelContactPicker implements ContactPicker {
  ChannelContactPicker({this.onLeave, this.onBack});

  /// Around the picker, so the lock allows the time away.
  final VoidCallback? onLeave;
  final VoidCallback? onBack;

  static const _channel = MethodChannel('chatdogaroto/contacts');

  @override
  Future<PickedContact?> pick() async {
    onLeave?.call();
    try {
      final picked = await _channel.invokeMapMethod<String, Object?>('pick');
      if (picked == null) return null;
      return (
        name: picked['name'] as String? ?? '',
        phone: picked['phone'] as String? ?? '',
      );
    } finally {
      onBack?.call();
    }
  }
}

/// The system picker, where there is one (Android); null elsewhere and in
/// tests, which set a fake.
ContactPicker? contactPicker;
