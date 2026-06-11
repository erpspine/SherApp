import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small per-trip cache for odometer logs that have already been fetched from
/// the backend. This lets the driver reopen a trip offline and still see the
/// previously-synced readings, while unsynced rows continue to come from the
/// outbox service.
class OdometerLogsCacheService {
  static const String _dataPrefix = 'odometer_logs_cache_v1_';
  static const String _savedAtPrefix = 'odometer_logs_cache_saved_at_v1_';

  static String _dataKey(dynamic tripId) => '$_dataPrefix${tripId.toString()}';
  static String _savedAtKey(dynamic tripId) =>
      '$_savedAtPrefix${tripId.toString()}';

  static Future<void> save(dynamic tripId, List<dynamic> logs) async {
    if (tripId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey(tripId), jsonEncode(logs));
    await prefs.setInt(
      _savedAtKey(tripId),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<List<Map<String, dynamic>>?> read(dynamic tripId) async {
    if (tripId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataKey(tripId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> savedAt(dynamic tripId) async {
    if (tripId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_savedAtKey(tripId));
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
