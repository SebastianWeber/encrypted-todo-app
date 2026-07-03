import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/todo.dart';
import 'format.dart';
import 'todo_edit_screen.dart';
import 'todo_list_view.dart';

/// Kalendarische Aufbereitung: Monatsraster mit Markierungen, darunter die
/// Agenda des gewählten Tags. Überfällige und terminlose ToDos in eigenen
/// Bereichen.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, required this.state});

  final AppState state;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month; // erster Tag des angezeigten Monats
  DateTime _selected = dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  Map<DateTime, List<Todo>> get _byDay {
    final map = <DateTime, List<Todo>>{};
    for (final t in widget.state.todos) {
      if (t.due == null) continue;
      map.putIfAbsent(dateOnly(t.due!), () => []).add(t);
    }
    return map;
  }

  void _shiftMonth(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta, 1);
      });

  Future<void> _edit(Todo todo) async {
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(builder: (_) => TodoEditScreen(todo: todo)),
    );
    if (result is Todo) await widget.state.saveTodo(result);
    if (result == TodoEditScreen.deleted) await widget.state.deleteTodo(todo);
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    final overdue = widget.state.todos
        .where((t) => t.isOverdue)
        .toList()
      ..sort((a, b) => a.due!.compareTo(b.due!));
    final noDue = widget.state.todos
        .where((t) => !t.isDone && t.due == null)
        .toList();
    // Kopie statt in-place: byDay kann leere unveränderliche Listen liefern.
    final selectedTodos = [...?byDay[_selected]]
      ..sort((a, b) => a.due!.compareTo(b.due!));

    // Raster: Montag als Wochenstart.
    final firstWeekday = _month.weekday; // 1 = Mo
    final gridStart = _month.subtract(Duration(days: firstWeekday - 1));
    final today = dateOnly(DateTime.now());

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Center(
                  child: Text(
                    '${kMonths[_month.month - 1]} ${_month.year}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  final now = DateTime.now();
                  _month = DateTime(now.year, now.month, 1);
                  _selected = dateOnly(now);
                }),
                child: const Text('Heute'),
              ),
              IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final wd in kWeekdaysShort)
                Expanded(
                  child: Center(
                    child: Text(wd,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < 6; week++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (var wd = 0; wd < 7; wd++)
                  Expanded(
                    child: _dayCell(
                      gridStart.add(Duration(days: week * 7 + wd)),
                      byDay,
                      today,
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 24),
        if (overdue.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Überfällig',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.red)),
          ),
          for (final t in overdue)
            TodoTile(
                todo: t,
                onTap: () => _edit(t),
                onDone: (v) => widget.state.setDone(t, v)),
          const Divider(height: 24),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            humanDay(_selected) == formatDate(_selected)
                ? formatDate(_selected)
                : '${humanDay(_selected)} · ${formatDate(_selected)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (selectedTodos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Keine ToDos an diesem Tag.'),
          )
        else
          for (final t in selectedTodos)
            TodoTile(
                todo: t,
                onTap: () => _edit(t),
                onDone: (v) => widget.state.setDone(t, v)),
        if (noDue.isNotEmpty) ...[
          const Divider(height: 24),
          ExpansionTile(
            title: Text('Ohne Termin (${noDue.length})'),
            children: [
              for (final t in noDue)
                TodoTile(
                    todo: t,
                    onTap: () => _edit(t),
                    onDone: (v) => widget.state.setDone(t, v)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dayCell(
      DateTime day, Map<DateTime, List<Todo>> byDay, DateTime today) {
    final inMonth = day.month == _month.month;
    final isToday = isSameDay(day, today);
    final isSelected = isSameDay(day, _selected);
    final todos = byDay[dateOnly(day)] ?? const <Todo>[];
    final open = todos.where((t) => !t.isDone).length;
    final hasOverdue = todos.any((t) => t.isOverdue);

    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selected = dateOnly(day)),
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? scheme.primaryContainer
              : isToday
                  ? scheme.surfaceContainerHighest
                  : null,
          border: isToday ? Border.all(color: scheme.primary) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.bold : null,
                color: inMonth
                    ? null
                    : Theme.of(context).disabledColor,
              ),
            ),
            const SizedBox(height: 2),
            if (todos.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < todos.length.clamp(0, 3); i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasOverdue
                            ? Colors.red
                            : open > 0
                                ? scheme.primary
                                : Theme.of(context).disabledColor,
                      ),
                    ),
                ],
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
