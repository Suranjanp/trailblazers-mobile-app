
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ScheduleService {
  static const String _storageKey = 'trailblazer-schedule';

  /// Loads all saved schedule entries.
  static Future<List<Map<String, dynamic>>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();

    final rawData = prefs.getString(_storageKey);

    if (rawData == null || rawData.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(rawData);

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Saves all schedule entries.
  static Future<void> saveEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _storageKey,
      jsonEncode(entries),
    );
  }
}
