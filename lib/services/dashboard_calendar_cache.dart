import 'package:flutter/foundation.dart';

/// Shares read-only Google Calendar events loaded by [ScheduleScreen] with the
/// Home dashboard while the application is running.
///
/// This cache provides a lightweight in-memory bridge between the two screens:
/// ScheduleScreen remains responsible for loading calendar data, while the
/// dashboard can listen for changes without making a separate Google Calendar
/// request.
class DashboardCalendarCache extends ChangeNotifier {
  DashboardCalendarCache._();

  /// Shared cache instance used by the schedule and home screens.
  static final DashboardCalendarCache instance = DashboardCalendarCache._();

  // The cached event maps are copied when written and when exposed so callers
  // cannot directly add or remove entries in the cache's top-level event list.
  List<Map<String, dynamic>> _events = [];

  // Timestamp of the most recent successful cache update. A null value means
  // the cache has not been populated (or has been explicitly cleared).
  DateTime? _loadedAt;

  /// Returns a copy of the cached events.
  ///
  /// Each map is copied as well, preventing callers from changing the cached
  /// top-level event fields through a returned map.
  List<Map<String, dynamic>> get events =>
      _events.map((event) => Map<String, dynamic>.from(event)).toList();

  /// Time when [update] last refreshed the cache, or null when empty.
  DateTime? get loadedAt => _loadedAt;

  /// Replaces the cached events and notifies all listening widgets.
  ///
  /// A defensive copy is stored so later changes to the caller's list or
  /// event maps do not alter the cached top-level data.
  void update(List<Map<String, dynamic>> events) {
    _events = events.map((event) => Map<String, dynamic>.from(event)).toList();
    _loadedAt = DateTime.now();
    notifyListeners();
  }

  /// Removes all cached events and resets the refresh timestamp.
  ///
  /// Listeners are notified so the Home dashboard can immediately reflect the
  /// cleared state rather than continuing to display stale calendar entries.
  void clear() {
    _events = [];
    _loadedAt = null;
    notifyListeners();
  }
}
