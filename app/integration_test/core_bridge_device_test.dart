// Runs the bridge and event cases on a device (one file, so the app is
// installed only once):
//   flutter test integration_test -d <device-id>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/core_bridge_cases.dart';
import '../test/core_events_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('bridge', defineCoreBridgeCases);
  group('events', defineCoreEventsCases);
}
