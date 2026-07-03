/// Deutsche Datums-Formatierung ohne intl-Initialisierungsaufwand.
library;

const List<String> kWeekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const List<String> kMonths = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';

String formatTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String formatDateTime(DateTime d) => '${formatDate(d)}, ${formatTime(d)} Uhr';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Heute", "Morgen", "Gestern" oder Datum.
String humanDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final day = dateOnly(d);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Heute';
  if (diff == 1) return 'Morgen';
  if (diff == -1) return 'Gestern';
  return formatDate(d);
}

/// Kompakte Fälligkeitsangabe für Listeneinträge.
String dueLabel(DateTime due, bool withTime) =>
    withTime ? '${humanDay(due)}, ${formatTime(due)}' : humanDay(due);
