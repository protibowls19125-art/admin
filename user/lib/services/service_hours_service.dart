import 'package:flutter/material.dart';
import 'supabase_service.dart';

/// Reads per order-type availability windows (set by the admin) and tells the
/// order form whether dine_in / takeaway / delivery can be ordered right now.
class ServiceHoursService {
  static final _instance = ServiceHoursService._();
  factory ServiceHoursService() => _instance;
  ServiceHoursService._();

  Map<String, dynamic> _hours = {};

  Future<void> load() async {
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'service_hours')
          .maybeSingle();
      _hours = (res?['value'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {/* fail open — no config means everything available */}
  }

  Map<String, dynamic>? _cfg(String type) =>
      (_hours[type] as Map?)?.cast<String, dynamic>();

  /// True if this order type can be ordered at the current local time.
  /// With split_hours on, it's available during EITHER window (morning or
  /// evening) — a lunch/dinner-only kitchen closed in the afternoon.
  bool isAvailable(String type) {
    final c = _cfg(type);
    if (c == null) return true; // no config → allow
    if ((c['enabled'] as bool?) == false) return false;
    final windows = _windows(c);
    if (windows.isEmpty) return true;
    final now = TimeOfDay.fromDateTime(DateTime.now());
    final n = now.hour * 60 + now.minute;
    return windows.any((w) {
      final o = w.$1.hour * 60 + w.$1.minute;
      final cl = w.$2.hour * 60 + w.$2.minute;
      return n >= o && n < cl;
    });
  }

  /// A friendly window label, e.g. "9:00 AM – 9:00 PM", or with split_hours,
  /// "9:00 AM – 2:00 PM, 6:00 PM – 10:00 PM".
  String label(String type) {
    final c = _cfg(type);
    if (c == null) return '';
    if ((c['enabled'] as bool?) == false) return 'Currently unavailable';
    final parts = <String>[];
    final o = c['open'] as String?;
    final cl = c['close'] as String?;
    if (o != null && cl != null) parts.add('${_fmt(o)} – ${_fmt(cl)}');
    if ((c['split_hours'] as bool?) == true) {
      final o2 = c['open2'] as String?;
      final cl2 = c['close2'] as String?;
      if (o2 != null && cl2 != null) parts.add('${_fmt(o2)} – ${_fmt(cl2)}');
    }
    return parts.join(', ');
  }

  /// Resolves a type's config into 1 or 2 (open, close) windows.
  List<(TimeOfDay, TimeOfDay)> _windows(Map<String, dynamic> c) {
    final windows = <(TimeOfDay, TimeOfDay)>[];
    final open = _parse(c['open'] as String?);
    final close = _parse(c['close'] as String?);
    if (open != null && close != null) windows.add((open, close));
    if ((c['split_hours'] as bool?) == true) {
      final open2 = _parse(c['open2'] as String?);
      final close2 = _parse(c['close2'] as String?);
      if (open2 != null && close2 != null) windows.add((open2, close2));
    }
    return windows;
  }

  TimeOfDay? _parse(String? s) {
    if (s == null || !s.contains(':')) return null;
    final p = s.split(':');
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(String? s) {
    final t = _parse(s);
    if (t == null) return s ?? '';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
  }
}
