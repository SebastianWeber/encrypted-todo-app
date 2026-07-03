import 'package:encrypted_todo_app/src/models/todo.dart';
import 'package:encrypted_todo_app/src/ui/calendar_view.dart';
import 'package:flutter_test/flutter_test.dart';

Todo _range(String title, DateTime start, DateTime due) =>
    Todo(title: title, start: start, due: due);

void main() {
  test('Überlappende Zeiträume bekommen verschiedene Spuren', () {
    final a = _range('A', DateTime(2026, 7, 1), DateTime(2026, 7, 5));
    final b = _range('B', DateTime(2026, 7, 3), DateTime(2026, 7, 8));
    final c = _range('C', DateTime(2026, 7, 4), DateTime(2026, 7, 6));

    final lanes = assignCalendarLanes([a, b, c]);

    expect(lanes[a.id], isNot(lanes[b.id]));
    expect(lanes[a.id], isNot(lanes[c.id]));
    expect(lanes[b.id], isNot(lanes[c.id]));
  });

  test('Nicht überlappende Zeiträume teilen sich eine Spur', () {
    final a = _range('A', DateTime(2026, 7, 1), DateTime(2026, 7, 3));
    final b = _range('B', DateTime(2026, 7, 4), DateTime(2026, 7, 6));

    final lanes = assignCalendarLanes([a, b]);

    expect(lanes[a.id], 0);
    expect(lanes[b.id], 0);
  });

  test('Bandfarbe ist stabil pro ToDo', () {
    final t = _range('X', DateTime(2026, 7, 1), DateTime(2026, 7, 2));
    expect(bandColorFor(t), bandColorFor(t.copy()));
  });
}
