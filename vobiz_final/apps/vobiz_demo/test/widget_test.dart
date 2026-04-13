import 'package:flutter_test/flutter_test.dart';

import 'package:vobiz_demo/app.dart';

void main() {
  testWidgets('shows the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VobizDemoApp());

    expect(find.text('Vobiz SDK Demo'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
