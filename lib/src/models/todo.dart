import 'package:uuid/uuid.dart';

const int kSchemaVersion = 1;

/// Status eines ToDos, angelehnt an RFC 5545 VTODO STATUS.
enum TodoStatus {
  open('open', 'Offen'),
  inProgress('in_progress', 'In Arbeit'),
  done('done', 'Erledigt'),
  cancelled('cancelled', 'Abgebrochen');

  const TodoStatus(this.code, this.label);
  final String code;
  final String label;

  static TodoStatus fromCode(String code) =>
      TodoStatus.values.firstWhere((s) => s.code == code,
          orElse: () => TodoStatus.open);
}

enum TodoPriority {
  none('none', 'Keine'),
  low('low', 'Niedrig'),
  medium('medium', 'Mittel'),
  high('high', 'Hoch');

  const TodoPriority(this.code, this.label);
  final String code;
  final String label;

  static TodoPriority fromCode(String code) =>
      TodoPriority.values.firstWhere((p) => p.code == code,
          orElse: () => TodoPriority.none);
}

class Subtask {
  Subtask({required this.text, this.done = false});

  String text;
  bool done;

  Map<String, dynamic> toJson() => {'text': text, 'done': done};

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
        text: json['text'] as String? ?? '',
        done: json['done'] as bool? ?? false,
      );
}

enum RecurrenceUnit {
  daily('daily', 'Tag(e)'),
  weekly('weekly', 'Woche(n)'),
  monthly('monthly', 'Monat(e)'),
  yearly('yearly', 'Jahr(e)');

  const RecurrenceUnit(this.code, this.label);
  final String code;
  final String label;

  static RecurrenceUnit fromCode(String code) =>
      RecurrenceUnit.values.firstWhere((u) => u.code == code,
          orElse: () => RecurrenceUnit.daily);
}

/// Vereinfachte Wiederholungsregel: alle [interval] Einheiten.
class Recurrence {
  const Recurrence({required this.unit, this.interval = 1});

  final RecurrenceUnit unit;
  final int interval;

  Map<String, dynamic> toJson() => {'unit': unit.code, 'interval': interval};

  factory Recurrence.fromJson(Map<String, dynamic> json) => Recurrence(
        unit: RecurrenceUnit.fromCode(json['unit'] as String? ?? 'daily'),
        interval: (json['interval'] as num?)?.toInt() ?? 1,
      );

  String get label =>
      interval == 1 ? 'Jede(n) ${unit.label}' : 'Alle $interval ${unit.label}';
}

class Todo {
  Todo({
    String? id,
    required this.title,
    this.description = '',
    this.status = TodoStatus.open,
    this.priority = TodoPriority.none,
    this.due,
    this.dueHasTime = false,
    this.start,
    this.completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    this.list,
    List<Subtask>? subtasks,
    this.recurrence,
    List<DateTime>? reminders,
    this.schemaVersion = kSchemaVersion,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [],
        subtasks = subtasks ?? [],
        reminders = reminders ?? [];

  final String id;
  String title;
  String description;
  TodoStatus status;
  TodoPriority priority;

  /// Fälligkeit; Grundlage der Kalenderansicht.
  DateTime? due;

  /// Ob [due] eine Uhrzeit trägt (sonst ganztägig).
  bool dueHasTime;

  DateTime? start;
  DateTime? completedAt;
  final DateTime createdAt;
  DateTime updatedAt;
  List<String> tags;
  String? list;
  List<Subtask> subtasks;
  Recurrence? recurrence;
  List<DateTime> reminders;
  final int schemaVersion;

  bool get isDone =>
      status == TodoStatus.done || status == TodoStatus.cancelled;

  bool get isOverdue {
    if (isDone || due == null) return false;
    final now = DateTime.now();
    if (dueHasTime) return due!.isBefore(now);
    final endOfDay = DateTime(due!.year, due!.month, due!.day, 23, 59, 59);
    return endOfDay.isBefore(now);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.code,
        'priority': priority.code,
        'due': due?.toIso8601String(),
        'due_has_time': dueHasTime,
        'start': start?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'tags': tags,
        'list': list,
        'subtasks': subtasks.map((s) => s.toJson()).toList(),
        'recurrence': recurrence?.toJson(),
        'reminders': reminders.map((r) => r.toIso8601String()).toList(),
        'schema_version': schemaVersion,
      };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        status: TodoStatus.fromCode(json['status'] as String? ?? 'open'),
        priority:
            TodoPriority.fromCode(json['priority'] as String? ?? 'none'),
        due: _parseDate(json['due']),
        dueHasTime: json['due_has_time'] as bool? ?? false,
        start: _parseDate(json['start']),
        completedAt: _parseDate(json['completed_at']),
        createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
        tags: (json['tags'] as List?)?.cast<String>() ?? [],
        list: json['list'] as String?,
        subtasks: (json['subtasks'] as List?)
                ?.map((s) => Subtask.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        recurrence: json['recurrence'] == null
            ? null
            : Recurrence.fromJson(json['recurrence'] as Map<String, dynamic>),
        reminders: (json['reminders'] as List?)
                ?.map((r) => DateTime.parse(r as String))
                .toList() ??
            [],
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      );

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.tryParse(value as String);

  /// Tiefe Kopie (für Bearbeitung ohne Seiteneffekte).
  Todo copy() => Todo.fromJson(toJson());
}

/// Kompakter Index-Eintrag für index.enc (schneller Bootstrap neuer Geräte).
class IndexEntry {
  const IndexEntry({
    required this.id,
    required this.title,
    required this.status,
    this.due,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final TodoStatus status;
  final DateTime? due;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.code,
        'due': due?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory IndexEntry.fromJson(Map<String, dynamic> json) => IndexEntry(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        status: TodoStatus.fromCode(json['status'] as String? ?? 'open'),
        due: json['due'] == null
            ? null
            : DateTime.tryParse(json['due'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  factory IndexEntry.fromTodo(Todo todo) => IndexEntry(
        id: todo.id,
        title: todo.title,
        status: todo.status,
        due: todo.due,
        updatedAt: todo.updatedAt,
      );
}
