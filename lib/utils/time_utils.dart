class TimeUtils {
  TimeUtils._();

  static DateTime parseApiTime(String raw) {
    return DateTime.parse(raw).toLocal();
  }

  static String formatTime(String? raw) {
    if (raw == null || raw.isEmpty || raw == '--') return '--';
    try {
      final dt = parseApiTime(raw);
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final h = hour % 12 == 0 ? 12 : hour % 12;
      return '$h:$minute $period';
    } catch (_) {
      return raw;
    }
  }

  static String formatDateTimeShort(String? raw) {
    if (raw == null || raw.isEmpty || raw == '--') return '-';
    try {
      final dt = parseApiTime(raw);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.length >= 16 ? raw.substring(0, 16) : raw;
    }
  }

  static String formatHistoryDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = parseApiTime(raw);
      return '${dt.day} ${monthName(dt.month)}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  static String formatTwentyFourHour(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = parseApiTime(raw);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  static String monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
