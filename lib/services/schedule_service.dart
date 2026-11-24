import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Provides local persistence for Trailblazer schedule entries.
///
/// This service is intentionally small and static: screens can load or save
/// the complete schedule without creating a service instance. Schedule data is
/// serialized as JSON and stored on the device through SharedPreferences.
class ScheduleService {
  // Keep the preference key stable so existing schedules remain available
  // across app updates.
  static const String _storageKey = 'trailblazer-schedule';

  /// Loads all saved schedule entries.
  ///
  /// Returns an empty list when no schedule has been saved, when the stored
  /// value is not a JSON list, or when the stored JSON cannot be decoded.
  static Future<List<Map<String, dynamic>>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();

    // The complete schedule is stored as one JSON string in local preferences.
    final rawData = prefs.getString(_storageKey);

    if (rawData == null || rawData.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(rawData);

      // Validate the top-level structure before attempting to convert entries.
      if (decoded is! List) {
        return [];
      }

      // Ignore list elements that are not map-shaped schedule records, then
      // normalize each accepted map to the dynamic-key/value type used by the
      // rest of the schedule feature.
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      // Treat malformed or incompatible stored data as an empty schedule.
      // This keeps a damaged preference value from crashing the schedule UI.
      return [];
    }
  }

  /// Saves all schedule entries.
  ///
  /// The caller supplies the full current list; this method replaces the
  /// previously stored JSON snapshot rather than appending individual entries.
  static Future<void> saveEntries(
    List<Map<String, dynamic>> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // JSON provides a compact, persistent representation of the schedule maps.
    await prefs.setString(
      _storageKey,
      jsonEncode(entries),
    );
  }
}
