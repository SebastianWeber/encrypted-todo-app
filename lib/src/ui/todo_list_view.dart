import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/todo.dart';
import 'format.dart';
import 'todo_edit_screen.dart';

enum _ShowFilter { open, all, done }

/// Listenansicht: Suche, Status-/Tag-Filter, Gruppierung nach Fälligkeit.
class TodoListView extends StatefulWidget {
  const TodoListView({super.key, required this.state});

  final AppState state;

  @override
  State<TodoListView> createState() => _TodoListViewState();
}

class _TodoListViewState extends State<TodoListView> {
  String _search = '';
  _ShowFilter _show = _ShowFilter.open;
  final Set<String> _tagFilter = {};

  List<Todo> get _filtered {
    final q = _search.toLowerCase();
    return widget.state.todos.where((t) {
      switch (_show) {
        case _ShowFilter.open:
          if (t.isDone) return false;
        case _ShowFilter.done:
          if (!t.isDone) return false;
        case _ShowFilter.all:
          break;
      }
      if (_tagFilter.isNotEmpty && !t.tags.any(_tagFilter.contains)) {
        return false;
      }
      if (q.isNotEmpty &&
          !t.title.toLowerCase().contains(q) &&
          !t.description.toLowerCase().contains(q) &&
          !t.tags.any((tag) => tag.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Gruppen: Überfällig / Heute / Morgen / Nächste 7 Tage / Später /
  /// Ohne Termin / Erledigt.
  Map<String, List<Todo>> get _grouped {
    final groups = <String, List<Todo>>{};
    final today = dateOnly(DateTime.now());
    for (final t in _filtered) {
      final String group;
      if (t.isDone) {
        group = 'Erledigt';
      } else if (t.due == null) {
        group = 'Ohne Termin';
      } else if (t.isOverdue) {
        group = 'Überfällig';
      } else {
        final diff = dateOnly(t.due!).difference(today).inDays;
        if (diff <= 0) {
          group = 'Heute';
        } else if (diff == 1) {
          group = 'Morgen';
        } else if (diff <= 7) {
          group = 'Nächste 7 Tage';
        } else {
          group = 'Später';
        }
      }
      groups.putIfAbsent(group, () => []).add(t);
    }
    for (final list in groups.values) {
      list.sort(_compareTodos);
    }
    const order = [
      'Überfällig', 'Heute', 'Morgen', 'Nächste 7 Tage',
      'Später', 'Ohne Termin', 'Erledigt',
    ];
    return {
      for (final g in order)
        if (groups.containsKey(g)) g: groups[g]!,
    };
  }

  static int _compareTodos(Todo a, Todo b) {
    if (a.due != null && b.due != null) {
      final c = a.due!.compareTo(b.due!);
      if (c != 0) return c;
    } else if (a.due != null) {
      return -1;
    } else if (b.due != null) {
      return 1;
    }
    return b.priority.index.compareTo(a.priority.index);
  }

  Future<void> _edit(Todo todo) async {
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(builder: (_) => TodoEditScreen(todo: todo)),
    );
    if (result is Todo) await widget.state.saveTodo(result);
    if (result == TodoEditScreen.deleted) await widget.state.deleteTodo(todo);
  }

  @override
  Widget build(BuildContext context) {
    final allTags =
        widget.state.todos.expand((t) => t.tags).toSet().toList()..sort();
    final grouped = _grouped;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Suchen …',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip('Offene', _ShowFilter.open),
              _filterChip('Alle', _ShowFilter.all),
              _filterChip('Erledigte', _ShowFilter.done),
              if (allTags.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: VerticalDivider(),
                ),
              for (final tag in allTags)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('#$tag'),
                    selected: _tagFilter.contains(tag),
                    onSelected: (sel) => setState(() =>
                        sel ? _tagFilter.add(tag) : _tagFilter.remove(tag)),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: grouped.isEmpty
              ? const Center(child: Text('Keine ToDos gefunden.'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final entry in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          entry.key,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: entry.key == 'Überfällig'
                                    ? Colors.red
                                    : null,
                              ),
                        ),
                      ),
                      for (final todo in entry.value)
                        TodoTile(
                          todo: todo,
                          onTap: () => _edit(todo),
                          onDone: (v) => widget.state.setDone(todo, v),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _ShowFilter value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _show == value,
          onSelected: (_) => setState(() => _show = value),
        ),
      );
}

class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onTap,
    required this.onDone,
  });

  final Todo todo;
  final VoidCallback onTap;
  final ValueChanged<bool> onDone;

  static const _priorityColors = {
    TodoPriority.high: Colors.red,
    TodoPriority.medium: Colors.orange,
    TodoPriority.low: Colors.blue,
  };

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (todo.due != null) dueLabel(todo.due!, todo.dueHasTime),
      if (todo.subtasks.isNotEmpty)
        '${todo.subtasks.where((s) => s.done).length}/${todo.subtasks.length} Teilschritte',
      if (todo.list != null && todo.list!.isNotEmpty) todo.list!,
      ...todo.tags.map((t) => '#$t'),
    ];

    return ListTile(
      leading: Checkbox(
        value: todo.isDone,
        onChanged: (v) => onDone(v ?? false),
      ),
      title: Text(
        todo.title,
        style: todo.isDone
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: todo.isOverdue ? Colors.red : null),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (todo.recurrence != null)
            const Icon(Icons.repeat, size: 18),
          if (todo.reminders.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.notifications_none, size: 18),
            ),
          if (_priorityColors.containsKey(todo.priority))
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.flag,
                  size: 18, color: _priorityColors[todo.priority]),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
