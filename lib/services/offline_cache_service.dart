import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheService {
  static const String _prefix = 'offline_cache_v1_';

  static Future<void> save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'value': value,
    });
    await prefs.setString('$_prefix$key', payload);
  }

  static Future<dynamic> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      return parsed['value'];
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastSavedAt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      final stamp = parsed['savedAt']?.toString();
      if (stamp == null) return null;
      return DateTime.tryParse(stamp);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
