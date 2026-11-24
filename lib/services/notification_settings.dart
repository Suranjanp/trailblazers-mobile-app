import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Stores the user's local notification preferences for Trailblazer.
///
/// Preferences are saved on this device. Notification permission is requested
/// only when the user turns the main Notifications switch on.
class NotificationSettings extends ChangeNotifier {
  NotificationSettings._();

  static final NotificationSettings instance = NotificationSettings._();

  static const String _enabledKey = 'notification_settings_enabled';
  static const String _scheduleRemindersKey =
      'notification_settings_schedule_reminders';
  static const String _dailySummaryKey =
      'notification_settings_daily_summary';
  static const String _motivationKey = 'notification_settings_motivation';
  static const String _reminderLeadMinutesKey =
      'notification_settings_reminder_lead_minutes';

  bool _enabled = false;
  bool _scheduleReminders = true;
  bool _dailySummary = false;
  bool _motivation = false;
  int _reminderLeadMinutes = 15;
  bool _isRequestingPermission = false;

  bool get enabled => _enabled;
  bool get scheduleReminders => _scheduleReminders;
  bool get dailySummary => _dailySummary;
  bool get motivation => _motivation;
  int get reminderLeadMinutes => _reminderLeadMinutes;
  bool get isRequestingPermission => _isRequestingPermission;

  static const List<int> reminderLeadMinuteOptions = [5, 10, 15, 30, 60];

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();

    _enabled = preferences.get(_enabledKey) == true;
    _scheduleReminders = preferences.get(_scheduleRemindersKey) != false;
    _dailySummary = preferences.get(_dailySummaryKey) == true;
    _motivation = preferences.get(_motivationKey) == true;

    final savedLeadTime = preferences.get(_reminderLeadMinutesKey);
    _reminderLeadMinutes = savedLeadTime is int &&
            reminderLeadMinuteOptions.contains(savedLeadTime)
        ? savedLeadTime
        : 15;

    notifyListeners();
  }

  /// Enables notifications only after runtime permission has been granted.
  /// Returns false if the user declines or permission cannot be obtained.
  Future<bool> setEnabled(bool value) async {
    if (value == _enabled) return true;

    if (value) {
      _isRequestingPermission = true;
      notifyListeners();

      var granted = false;
      try {
        granted = await NotificationService.instance.requestPermissions();
      } catch (error) {
        debugPrint('Trailblazer notification permission request failed: $error');
      } finally {
        _isRequestingPermission = false;
      }

      if (!granted) {
        notifyListeners();
        return false;
      }
    }

    _enabled = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);

    if (!value && NotificationService.instance.isInitialized) {
      await NotificationService.instance.cancelAllNotifications();
    }

    return true;
  }

  Future<void> setScheduleReminders(bool value) async {
    _scheduleReminders = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_scheduleRemindersKey, value);
  }

  Future<void> setDailySummary(bool value) async {
    _dailySummary = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_dailySummaryKey, value);
  }

  Future<void> setMotivation(bool value) async {
    _motivation = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_motivationKey, value);
  }

  Future<void> setReminderLeadMinutes(int value) async {
    if (!reminderLeadMinuteOptions.contains(value)) return;

    _reminderLeadMinutes = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_reminderLeadMinutesKey, value);
  }
}
