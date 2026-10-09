import 'package:flutter_test/flutter_test.dart';
import 'package:dine_master/main.dart';

void main() {
  testWidgets('Dine Master Login Screen Smoke Test', (WidgetTester tester) async {
    // Build our app and trigger a frame on login screen.
    await tester.pumpWidget(const MyApp(hasToken: false, initialLocation: '/'));
    await tester.pumpAndSettle();

    // Verify that the login screen header is displayed
    expect(find.text('DINE MASTER'), findsOneWidget);
    expect(find.text('Enterprise ERP & POS'), findsOneWidget);

    // Verify that username and password labels/fields are present
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    // Verify that login button is present
    expect(find.text('LOGIN'), findsOneWidget);
  });
}
