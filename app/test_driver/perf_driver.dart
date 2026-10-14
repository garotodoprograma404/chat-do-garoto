// Runs integration_test/scroll_perf_test.dart on a phone in profile mode
// and writes the frame summaries to build/integration_response_data.json
//:
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/scroll_perf_test.dart -d <phone>
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
