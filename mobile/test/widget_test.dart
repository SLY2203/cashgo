import 'package:flutter_test/flutter_test.dart';
import 'package:cashgo/main.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const CashGoApp());
    await tester.pumpAndSettle();
    expect(find.text('CashGo'), findsWidgets);
  });
}
