import 'package:flutter_test/flutter_test.dart'; // ✅ CORREGIDO
import 'package:tesis26/main.dart';

void main() {
  testWidgets('Smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MoniScanApp());
    expect(find.text('MoniScan'), findsOneWidget);
  });
}
