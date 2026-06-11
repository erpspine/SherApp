import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight on-device cache for the driver's trip list.
///
/// The driver app must remain useful when the device is offline (e.g. parked
/// at a remote site, deep in the basement, on a long-haul without coverage).
/// Without this cache `DriverTripsScreen` would render an empty list every
/// time the network call fails. We persist the last successful response under
/// a per-scope key so we can replay it on failure.
class TripsCacheService {
  TripsCacheService._();

  static const String _prefix = 'trips_cache_v1::';
  static const String _stampSuffix = '::stamp';

  /// Build the storage key for a given scope. We separate the
  /// "my assigned" feed from any admin-style "driver-by-id" feed so the two
  /// don't trample each other on shared devices.
  static String _key({required bool useCurrentAssignments, int? driverId}) {
    if (useCurrentAssignments) return '${_prefix}me';
    if (driverId != null) return '$_prefix$driverId';
    return '${_prefix}default';
  }

  /// Persist [trips] for later offline reads.
  ///
  /// Failures here are intentionally swallowed: caching is best-effort and
  /// must never break the live data path.
  static Future<void> save(
    List<dynamic> trips, {
    required bool useCurrentAssignments,
    int? driverId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(
        useCurrentAssignments: useCurrentAssignments,
        driverId: driverId,
      );
      await prefs.setString(key, jsonEncode(trips));
      await prefs.setInt(
        '$key$_stampSuffix',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Silently ignore – cache is non-essential.
    }
  }

  /// Read the previously cached trip list for this scope, or `null` if none.
  static Future<List<dynamic>?> read({
    required bool useCurrentAssignments,
    int? driverId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(
        useCurrentAssignments: useCurrentAssignments,
        driverId: driverId,
      );
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Timestamp (UTC) of the cached snapshot for [scope], or `null` if none.
  static Future<DateTime?> savedAt({
    required bool useCurrentAssignments,
    int? driverId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(
        useCurrentAssignments: useCurrentAssignments,
        driverId: driverId,
      );
      final stamp = prefs.getInt('$key$_stampSuffix');
      if (stamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(stamp);
    } catch (_) {
      return null;
    }
  }
}
