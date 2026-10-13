import 'package:intl/intl.dart';

/// Philippine peso formatting and the other small string helpers the UI needs.
class Fmt {
  const Fmt._();

  static final NumberFormat _peso = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static final NumberFormat _pesoWhole = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );

  static final DateFormat _dayMonth = DateFormat('d MMM yyyy');
  static final DateFormat _dayMonthTime = DateFormat('d MMM yyyy • h:mm a');
  static final DateFormat _time = DateFormat('h:mm a');

  /// ₱185.00
  static String peso(num value) => _peso.format(value);

  /// ₱185 — used where the brief omits decimals (e.g. the order card total).
  static String pesoWhole(num value) => _pesoWhole.format(value);

  /// 1 Oct 2026
  static String date(DateTime value) => _dayMonth.format(value);

  /// 1 Oct 2026 • 3:24 PM
  static String dateTime(DateTime value) => _dayMonthTime.format(value);

  /// 3:24 PM
  static String time(DateTime value) => _time.format(value);

  /// "now" / "5 min ago" / "3 h ago" / "2 d ago" / "1 Oct 2026".
  ///
  /// Used by the notifications inbox. Everything is compared in UTC so a stored
  /// server timestamp and a locally-clocked "now" do not disagree by the
  /// timezone offset. [now] is injectable so the tests do not depend on the wall
  /// clock.
  static String relative(DateTime value, {DateTime? now}) {
    final Duration d = (now ?? DateTime.now()).toUtc().difference(value.toUtc());
    if (d.inSeconds < 45) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return date(value.toLocal());
  }

  /// HL-2601-4820
  static String orderId(String raw) {
    if (raw.length >= 14) return raw;
    final String digits = raw.padLeft(10, '0').substring(raw.length > 10 ? raw.length - 10 : 0);
    return 'HL-${digits.substring(0, 4)}-${digits.substring(4, 8)}';
  }

  /// 0.3 km / 1.2 km / 12 km
  static String distance(num km) {
    if (km < 1) return '${(km * 1000).round()} m';
    final String s = km.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s} km';
  }

  /// "in 25 min" / "now"
  static String eta(Duration d) {
    if (d.inMinutes <= 0) return 'now';
    if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
    final int h = d.inHours;
    final int m = d.inMinutes % 60;
    return m == 0 ? 'in ${h}h' : 'in ${h}h ${m}m';
  }

  /// "2 items" / "1 item"
  static String itemCount(int n) => n == 1 ? '1 item' : '$n items';
}