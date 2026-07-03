import 'package:flutter/material.dart';

import '../models/todo.dart';
import 'format.dart';

/// Erstellen/Bearbeiten eines ToDos mit allen v1-Feldern.
///
/// Liefert per Navigator.pop: das gespeicherte [Todo], [deleted] oder null.
class TodoEditScreen extends StatefulWidget {
  const TodoEditScreen({super.key, this.todo});

  /// Sentinel-Rückgabewert für "ToDo löschen".
  static const Object deleted = 'deleted';

  final Todo? todo;

  @override
  State<TodoEditScreen> createState() => _TodoEditScreenState();
}

class _TodoEditScreenState extends State<TodoEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _tags;
  late final TextEditingController _list;
  final _subtaskInput = TextEditingController();
  final _intervalInput = TextEditingController(text: '1');

  late TodoStatus _status;
  late TodoPriority _priority;
  DateTime? _due;
  bool _dueHasTime = false;
  DateTime? _start;
  late List<Subtask> _subtasks;
  RecurrenceUnit? _recurrenceUnit;
  late List<DateTime> _reminders;

  bool get _isNew => widget.todo == null;

  @override
  void initState() {
    super.initState();
    final t = widget.todo;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _tags = TextEditingController(text: t?.tags.join(', ') ?? '');
    _list = TextEditingController(text: t?.list ?? '');
    _status = t?.status ?? TodoStatus.open;
    _priority = t?.priority ?? TodoPriority.none;
    _due = t?.due;
    _dueHasTime = t?.dueHasTime ?? false;
    _start = t?.start;
    _subtasks = t?.subtasks
            .map((s) => Subtask(text: s.text, done: s.done))
            .toList() ??
        [];
    _recurrenceUnit = t?.recurrence?.unit;
    _intervalInput.text = '${t?.recurrence?.interval ?? 1}';
    _reminders = List.of(t?.reminders ?? const []);
  }

  @override
  void dispose() {
    for (final c in [
      _title, _description, _tags, _list, _subtaskInput, _intervalInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Future<void> _pickDue() async {
    final date = await _pickDate(_due);
    if (date == null) return;
    setState(() {
      _due = _dueHasTime && _due != null
          ? DateTime(date.year, date.month, date.day, _due!.hour, _due!.minute)
          : date;
    });
  }

  Future<void> _pickDueTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _due != null && _dueHasTime
          ? TimeOfDay.fromDateTime(_due!)
          : const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return;
    final base = _due ?? DateTime.now();
    setState(() {
      _due = DateTime(base.year, base.month, base.day, time.hour, time.minute);
      _dueHasTime = true;
    });
  }

  Future<void> _addReminder() async {
    final date = await _pickDate(_due);
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time == null) return;
    setState(() => _reminders.add(
        DateTime(date.year, date.month, date.day, time.hour, time.minute)));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final tags = _tags.text
        .split(',')
        .map((t) => t.trim().replaceAll('#', ''))
        .where((t) => t.isNotEmpty)
        .toList();
    final interval = int.tryParse(_intervalInput.text) ?? 1;

    // Verdrehte Datumsangaben stillschweigend korrigieren.
    if (_start != null && _due != null && _start!.isAfter(_due!)) {
      final tmp = _start;
      _start = _due;
      _due = tmp;
    }

    final todo = widget.todo ?? Todo(title: _title.text.trim());
    todo
      ..title = _title.text.trim()
      ..description = _description.text.trim()
      ..status = _status
      ..priority = _priority
      ..due = _due
      ..dueHasTime = _dueHasTime
      ..start = _start
      ..tags = tags
      ..list = _list.text.trim().isEmpty ? null : _list.text.trim()
      ..subtasks = _subtasks
      ..recurrence = _recurrenceUnit == null
          ? null
          : Recurrence(unit: _recurrenceUnit!, interval: interval.clamp(1, 999))
      ..reminders = _reminders
      ..completedAt = _status == TodoStatus.done
          ? (todo.completedAt ?? DateTime.now())
          : null;
    Navigator.of(context).pop(todo);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ToDo löschen?'),
        content: Text('„${widget.todo!.title}" wird auf allen Geräten '
            'und im Repository gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(TodoEditScreen.deleted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neues ToDo' : 'ToDo bearbeiten'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _title,
                  autofocus: _isNew,
                  decoration: const InputDecoration(
                      labelText: 'Titel *', border: OutlineInputBorder()),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<TodoStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                          labelText: 'Status', border: OutlineInputBorder()),
                      items: [
                        for (final s in TodoStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<TodoPriority>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                          labelText: 'Priorität',
                          border: OutlineInputBorder()),
                      items: [
                        for (final p in TodoPriority.values)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                      onChanged: (v) => setState(() => _priority = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Termine'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(_due == null
                      ? 'Fälligkeitsdatum wählen'
                      : 'Fällig: ${formatDate(_due!)}'
                          '${_dueHasTime ? ', ${formatTime(_due!)} Uhr' : ''}'),
                  onTap: _pickDue,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_due != null)
                      IconButton(
                        tooltip: 'Uhrzeit setzen',
                        icon: const Icon(Icons.schedule),
                        onPressed: _pickDueTime,
                      ),
                    if (_due != null)
                      IconButton(
                        tooltip: 'Entfernen',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _due = null;
                          _dueHasTime = false;
                        }),
                      ),
                  ]),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_arrow),
                  title: Text(_start == null
                      ? 'Startdatum wählen (für mehrtägige ToDos)'
                      : 'Start: ${formatDate(_start!)}'),
                  onTap: () async {
                    final d = await _pickDate(_start);
                    if (d != null) setState(() => _start = d);
                  },
                  trailing: _start == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _start = null),
                        ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<RecurrenceUnit?>(
                      initialValue: _recurrenceUnit,
                      decoration: const InputDecoration(
                          labelText: 'Wiederholung',
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Keine')),
                        for (final u in RecurrenceUnit.values)
                          DropdownMenuItem(value: u, child: Text(u.label)),
                      ],
                      onChanged: (v) => setState(() => _recurrenceUnit = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: _intervalInput,
                      enabled: _recurrenceUnit != null,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Alle …',
                          border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Erinnerungen'),
                for (var i = 0; i < _reminders.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications),
                    title: Text(formatDateTime(_reminders[i])),
                    trailing: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _reminders.removeAt(i)),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _addReminder,
                  icon: const Icon(Icons.add_alert),
                  label: const Text('Erinnerung hinzufügen'),
                ),
                const SizedBox(height: 16),
                _sectionTitle('Teilschritte'),
                for (var i = 0; i < _subtasks.length; i++)
                  Row(children: [
                    Checkbox(
                      value: _subtasks[i].done,
                      onChanged: (v) =>
                          setState(() => _subtasks[i].done = v ?? false),
                    ),
                    Expanded(child: Text(_subtasks[i].text)),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _subtasks.removeAt(i)),
                    ),
                  ]),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _subtaskInput,
                      decoration: const InputDecoration(
                          hintText: 'Neuer Teilschritt …',
                          border: OutlineInputBorder(),
                          isDense: true),
                      onSubmitted: (_) => _addSubtask(),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.add), onPressed: _addSubtask),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Organisation'),
                TextFormField(
                  controller: _tags,
                  decoration: const InputDecoration(
                      labelText: 'Tags (durch Komma getrennt)',
                      hintText: 'z. B. arbeit, einkauf',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _list,
                  decoration: const InputDecoration(
                      labelText: 'Liste/Projekt',
                      hintText: 'z. B. Haushalt',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addSubtask() {
    final text = _subtaskInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(Subtask(text: text));
      _subtaskInput.clear();
    });
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
