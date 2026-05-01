import 'package:flutter_test/flutter_test.dart';

import 'package:class_schedule/main.dart';

void main() {
  testWidgets('App boots with the main app widget', (WidgetTester tester) async {
    await tester.pumpWidget(const ClassScheduleApp());

    expect(find.byType(ClassScheduleApp), findsOneWidget);
  });
}
