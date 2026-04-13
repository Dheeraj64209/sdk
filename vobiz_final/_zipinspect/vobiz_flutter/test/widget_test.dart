import 'package:flutter_test/flutter_test.dart';
import 'package:vobiz_mobile/main.dart';

void main() {
  testWidgets('renders the login screen by default', (tester) async {
    await tester.pumpWidget(const VobizApp());

    expect(find.text('Vobiz'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
