import 'package:encrypted_todo_app/src/models/recurrence_logic.dart';
import 'package:encrypted_todo_app/src/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Todo: JSON-Roundtrip mit allen Feldern', () {
    final todo = Todo(
      title: 'Steuererklärung',
      description: 'Belege sammeln\nFormular ausfüllen',
      status: TodoStatus.inProgress,
      priority: TodoPriority.high,
      due: DateTime(2026, 7, 31, 18, 0),
      dueHasTime: true,
      start: DateTime(2026, 7, 1),
      tags: ['finanzen', 'wichtig'],
      list: 'Privat',
      subtasks: [Subtask(text: 'Belege', done: true), Subtask(text: 'Formular')],
      recurrence: const Recurrence(unit: RecurrenceUnit.yearly),
      reminders: [DateTime(2026, 7, 25, 9, 0)],
    );

    final restored = Todo.fromJson(todo.toJson());

    expect(restored.id, todo.id);
    expect(restored.title, todo.title);
    expect(restored.description, todo.description);
    expect(restored.status, TodoStatus.inProgress);
    expect(restored.priority, TodoPriority.high);
    expect(restored.due, todo.due);
    expect(restored.dueHasTime, true);
    expect(restored.tags, ['finanzen', 'wichtig']);
    expect(restored.list, 'Privat');
    expect(restored.subtasks.length, 2);
    expect(restored.subtasks[0].done, true);
    expect(restored.recurrence!.unit, RecurrenceUnit.yearly);
    expect(restored.reminders, todo.reminders);
  });

  test('Todo: unbekannte Status-Codes fallen auf "open" zurück', () {
    final json = Todo(title: 'x').toJson()..['status'] = 'zukunftswert';
    expect(Todo.fromJson(json).status, TodoStatus.open);
  });

  test('isOverdue: ganztägig erst nach Tagesende überfällig', () {
    final today = DateTime.now();
    final todo = Todo(title: 'heute fällig')
      ..due = DateTime(today.year, today.month, today.day);
    expect(todo.isOverdue, false);

    todo.due = today.subtract(const Duration(days: 1));
    expect(todo.isOverdue, true);

    todo.status = TodoStatus.done;
    expect(todo.isOverdue, false);
  });

  group('Wiederholung', () {
    test('täglich/wöchentlich addieren Tage', () {
      final from = DateTime(2026, 7, 3);
      expect(
          nextOccurrence(
              from, const Recurrence(unit: RecurrenceUnit.daily, interval: 3)),
          DateTime(2026, 7, 6));
      expect(
          nextOccurrence(
              from, const Recurrence(unit: RecurrenceUnit.weekly)),
          DateTime(2026, 7, 10));
    });

    test('monatlich klemmt auf Monatsende', () {
      expect(
          nextOccurrence(DateTime(2026, 1, 31),
              const Recurrence(unit: RecurrenceUnit.monthly)),
          DateTime(2026, 2, 28));
      expect(
          nextOccurrence(DateTime(2028, 1, 31),
              const Recurrence(unit: RecurrenceUnit.monthly)),
          DateTime(2028, 2, 29)); // Schaltjahr
    });

    test('jährlich', () {
      expect(
          nextOccurrence(DateTime(2026, 7, 3),
              const Recurrence(unit: RecurrenceUnit.yearly)),
          DateTime(2027, 7, 3));
    });

    test('createNextInstance: neue Instanz, Subtasks zurückgesetzt', () {
      final done = Todo(
        title: 'Müll rausbringen',
        due: DateTime.now().add(const Duration(days: 1)),
        recurrence: const Recurrence(unit: RecurrenceUnit.weekly),
        subtasks: [Subtask(text: 'Tonne', done: true)],
      )..status = TodoStatus.done;

      final next = createNextInstance(done)!;

      expect(next.id, isNot(done.id));
      expect(next.status, TodoStatus.open);
      expect(next.due!.isAfter(done.due!), true);
      expect(next.subtasks.single.done, false);
      expect(next.recurrence, isNotNull);
    });

    test('createNextInstance: lange überfällige Wiederholung spult vor', () {
      final done = Todo(
        title: 'Gießen',
        due: DateTime.now().subtract(const Duration(days: 30)),
        recurrence: const Recurrence(unit: RecurrenceUnit.daily, interval: 7),
      )..status = TodoStatus.done;

      final next = createNextInstance(done)!;
      expect(next.due!.isAfter(DateTime.now().subtract(const Duration(days: 1))),
          true);
    });

    test('createNextInstance: null ohne Wiederholung', () {
      expect(createNextInstance(Todo(title: 'einmalig')), isNull);
    });
  });
}
