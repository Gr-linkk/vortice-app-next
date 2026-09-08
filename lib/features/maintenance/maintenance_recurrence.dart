/// Calendar and meter recurrence use independent targets; either can make work due.
class MaintenanceRecurrence {
  const MaintenanceRecurrence({
    required this.hours,
    required this.baseline,
    this.months,
    this.fixed = false,
    this.anchorHours,
    this.anchorDate,
    this.lastDate,
  });
  final int hours;
  final double baseline;
  final int? months;
  final bool fixed;
  final double? anchorHours;
  final DateTime? anchorDate, lastDate;

  double? nextHours(double completed) {
    if (hours == 0) return null;
    if (!fixed) return completed + hours;
    final anchor = anchorHours!;
    final step = ((completed - anchor) / hours).floor() + 1;
    return anchor + (step < 0 ? 0 : step) * hours;
  }

  DateTime? nextDate(DateTime completed) {
    if (months == null) return null;
    if (!fixed) return addMonths(completed, months!);
    final anchor = anchorDate!;
    var n =
        ((completed.year - anchor.year) * 12 +
            completed.month -
            anchor.month) ~/
        months!;
    if (n < 0) n = 0;
    var candidate = addMonths(anchor, n * months!);
    if (!candidate.isAfter(completed)) {
      candidate = addMonths(anchor, (n + 1) * months!);
    }
    return candidate;
  }

  static DateTime addMonths(DateTime date, int months) {
    final first = DateTime(date.year, date.month + months);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(
      first.year,
      first.month,
      date.day > lastDay ? lastDay : date.day,
    );
  }

  static DateTime? parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final date = DateTime.tryParse(value);
    return date != null && dateText(date) == value ? date : null;
  }

  static String dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String recurrenceSummary(Map<String, dynamic> plan, bool es) {
  final hours = (plan['interval_hours'] as num?) ?? 0;
  final months = plan['interval_months'];
  return [
    if (hours > 0) '${es ? 'Cada' : 'Every'} $hours h',
    if (months != null)
      '${es ? 'Cada' : 'Every'} $months ${es ? 'meses' : 'months'}',
    if (hours > 0 && months != null)
      es ? 'lo que ocurra primero' : 'whichever comes first',
  ].join(' · ');
}

String recurrenceDueText(Map<String, dynamic> plan, bool es) => [
  if (plan['next_due_hours'] != null) '${plan['next_due_hours']} h',
  if (plan['next_due_date'] != null) plan['next_due_date'].toString(),
].join(es ? ' o ' : ' or ');
