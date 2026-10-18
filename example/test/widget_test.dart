import 'package:flutter_test/flutter_test.dart';
import 'package:notifiable_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the connect screen before a key is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Public key'), findsOneWidget);
  });
}
