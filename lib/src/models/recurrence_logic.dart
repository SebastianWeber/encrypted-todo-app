import 'todo.dart';

/// Liefert die nächste Fälligkeit nach [from] gemäß [rule].
///
/// Monats-/Jahresschritte klemmen den Tag auf das Monatsende
/// (31.01. + 1 Monat -> 28./29.02.).
DateTime nextOccurrence(DateTime from, Recurrence rule) {
  switch (rule.unit) {
    case RecurrenceUnit.daily:
      return from.add(Duration(days: rule.interval));
    case RecurrenceUnit.weekly:
      return from.add(Duration(days: 7 * rule.interval));
    case RecurrenceUnit.monthly:
      return _addMonths(from, rule.interval);
    case RecurrenceUnit.yearly:
      return _addMonths(from, 12 * rule.interval);
  }
}

DateTime _addMonths(DateTime from, int months) {
  final zeroBased = from.month - 1 + months;
  final year = from.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final day = from.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, day, from.hour, from.minute);
}

int _daysInMonth(int year, int month) {
  final firstOfNext =
      month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  return firstOfNext.subtract(const Duration(days: 1)).day;
}

/// Erzeugt beim Erledigen eines wiederkehrenden ToDos die Folgeinstanz:
/// neues ToDo mit fortgeschriebener Fälligkeit, zurückgesetzten Subtasks
/// und verschobenen Erinnerungen. Liefert null, wenn keine Wiederholung.
Todo? createNextInstance(Todo completed) {
  final rule = completed.recurrence;
  if (rule == null) return null;

  final base = completed.due ?? DateTime.now();
  var next = nextOccurrence(base, rule);
  // Liegt die nächste Instanz immer noch in der Vergangenheit
  // (lange nicht erledigt), so weit vorspulen, bis sie in der Zukunft liegt.
  final now = DateTime.now();
  while (next.isBefore(now) &&
      DateTime(next.year, next.month, next.day)
          .isBefore(DateTime(now.year, now.month, now.day))) {
    next = nextOccurrence(next, rule);
  }

  final offset = completed.due == null ? null : next.difference(completed.due!);

  return Todo(
    title: completed.title,
    description: completed.description,
    status: TodoStatus.open,
    priority: completed.priority,
    due: next,
    dueHasTime: completed.dueHasTime,
    tags: List.of(completed.tags),
    list: completed.list,
    subtasks: completed.subtasks
        .map((s) => Subtask(text: s.text, done: false))
        .toList(),
    recurrence: rule,
    reminders: offset == null
        ? []
        : completed.reminders.map((r) => r.add(offset)).toList(),
  );
}
