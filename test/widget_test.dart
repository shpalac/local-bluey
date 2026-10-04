import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/main.dart';

void main() {
  testWidgets('app renders home screen', (tester) async {
    await tester.pumpWidget(const LocalBlueyApp());
    expect(find.text('Local Bluey'), findsOneWidget);
  });
}
