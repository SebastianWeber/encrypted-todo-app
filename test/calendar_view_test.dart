import 'package:encrypted_todo_app/src/app_state.dart';
import 'package:encrypted_todo_app/src/notifications/notification_service.dart';
import 'package:encrypted_todo_app/src/settings/app_config.dart';
import 'package:encrypted_todo_app/src/ui/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressionstest: Kalenderansicht zeigte im Release nur ein graues Feld
/// (Exception beim Bauen des Widgets).
void main() {
  testWidgets('CalendarView baut ohne Exception (leerer Zustand)',
      (tester) async {
    final state = AppState(
      configStore: AppConfigStore(),
      baseDir: 'unused',
      notifications: NotificationService(),
    );

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CalendarView(state: state))));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Monatstitel und Wochentagszeile sichtbar?
    expect(find.textContaining(RegExp(r'20\d\d')), findsWidgets);
    expect(find.text('Mo'), findsOneWidget);
    expect(find.text('Heute'), findsWidgets);
  });
}
