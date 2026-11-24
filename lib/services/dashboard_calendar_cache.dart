import 'package:flutter/foundation.dart';

/// Shares the read-only Google Calendar events loaded by ScheduleScreen with
/// the Home dashboard while the app is running.
class DashboardCalendarCache extends ChangeNotifier {
  DashboardCalendarCache._();

  static final DashboardCalendarCache instance = DashboardCalendarCache._();

  List<Map<String, dynamic>> _events = [];
  DateTime? _loadedAt;

  List<Map<String, dynamic>> get events =>
      _events.map((event) => Map<String, dynamic>.from(event)).toList();
  DateTime? get loadedAt => _loadedAt;

  void update(List<Map<String, dynamic>> events) {
    _events = events.map((event) => Map<String, dynamic>.from(event)).toList();
    _loadedAt = DateTime.now();
    notifyListeners();
  }

  void clear() {
    _events = [];
    _loadedAt = null;
    notifyListeners();
  }
}
