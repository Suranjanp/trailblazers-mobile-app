import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Stores the user's local notification preferences for Trailblazer.
///
/// Preferences are saved on this device. Notification permission is requested
/// only when the user turns the main Notifications switch on.
///
/// This singleton exposes preference changes through [ChangeNotifier], so
/// settings controls and other interested widgets can stay synchronized without
/// each screen reading SharedPreferences independently.
class NotificationSettings extends ChangeNotifier {
  NotificationSettings._();

  static final NotificationSettings instance = NotificationSettings._();

  // Stable keys keep saved preferences associated with the same settings
  // across app launches and future screen rebuilds.
  static const String _enabledKey = 'notification_settings_enabled';
  static const String _scheduleRemindersKey =
      'notification_settings_schedule_reminders';
  static const String _dailySummaryKey =
      'notification_settings_daily_summary';
  static const String _motivationKey = 'notification_settings_motivation';
  static const String _reminderLeadMinutesKey =
      'notification_settings_reminder_lead_minutes';

  // Defaults favor useful schedule reminders while leaving optional
  // notifications disabled until the user chooses to enable them.
  bool _enabled = false;
  bool _scheduleReminders = true;
  bool _dailySummary = false;
  bool _motivation = false;
  int _reminderLeadMinutes = 15;

  // Tracks the asynchronous OS permission prompt so the settings UI can show
  // a loading state and prevent misleading feedback while it is in progress.
  bool _isRequestingPermission = false;

  // Read-only accessors keep all preference mutations inside this class.
  bool get enabled => _enabled;
  bool get scheduleReminders => _scheduleReminders;
  bool get dailySummary => _dailySummary;
  bool get motivation => _motivation;
  int get reminderLeadMinutes => _reminderLeadMinutes;
  bool get isRequestingPermission => _isRequestingPermission;

  // Only these lead times are offered by the settings UI and accepted for
  // persistence, keeping reminder scheduling values predictable.
  static const List<int> reminderLeadMinuteOptions = [5, 10, 15, 30, 60];

  /// Loads saved notification preferences from device-local storage.
  ///
  /// Raw preference values are checked before use so missing or incorrectly
  /// typed entries fall back to the defaults declared above.
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();

    _enabled = preferences.get(_enabledKey) == true;
    _scheduleReminders = preferences.get(_scheduleRemindersKey) != false;
    _dailySummary = preferences.get(_dailySummaryKey) == true;
    _motivation = preferences.get(_motivationKey) == true;

    // Accept a saved lead time only when it is an integer in the supported
    // options; otherwise restore the standard 15-minute reminder interval.
    final savedLeadTime = preferences.get(_reminderLeadMinutesKey);
    _reminderLeadMinutes = savedLeadTime is int &&
            reminderLeadMinuteOptions.contains(savedLeadTime)
        ? savedLeadTime
        : 15;

    // Notify settings screens after the complete preference snapshot is loaded.
    notifyListeners();
  }

  /// Enables notifications only after runtime permission has been granted.
  /// Returns false if the user declines or permission cannot be obtained.
  Future<bool> setEnabled(bool value) async {
    // Avoid unnecessary permission prompts and writes when the requested
    // value already matches the current setting.
    if (value == _enabled) return true;

    if (value) {
      _isRequestingPermission = true;
      notifyListeners();

      var granted = false;
      try {
        // Delegate the platform-specific permission request to the central
        // notification service instead of handling Android/iOS here.
        granted = await NotificationService.instance.requestPermissions();
      } catch (error) {
        // A permission API failure should leave notifications disabled and
        // should not prevent the rest of the settings screen from functioning.
        debugPrint('Trailblazer notification permission request failed: $error');
      } finally {
        _isRequestingPermission = false;
      }

      if (!granted) {
        // Keep the persisted and in-memory enabled values unchanged when the
        // user declines permission or the platform request cannot be completed.
        notifyListeners();
        return false;
      }
    }

    // Update the observable state before persisting so listening widgets
    // immediately reflect the user's successful settings change.
    _enabled = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);

    // Turning the master switch off also removes queued/displayed alerts.
    // Other category preferences remain saved for the next time it is enabled.
    if (!value && NotificationService.instance.isInitialized) {
      await NotificationService.instance.cancelAllNotifications();
    }

    return true;
  }

  /// Enables or disables reminders for events in the user's schedule.
  Future<void> setScheduleReminders(bool value) async {
    _scheduleReminders = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_scheduleRemindersKey, value);
  }

  /// Enables or disables the optional daily summary preference.
  Future<void> setDailySummary(bool value) async {
    _dailySummary = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_dailySummaryKey, value);
  }

  /// Enables or disables optional motivational notifications.
  Future<void> setMotivation(bool value) async {
    _motivation = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_motivationKey, value);
  }

  /// Sets how many minutes before an event its reminder should appear.
  ///
  /// Unsupported values are ignored, ensuring callers can only persist one of
  /// the choices exposed by [reminderLeadMinuteOptions].
  Future<void> setReminderLeadMinutes(int value) async {
    if (!reminderLeadMinuteOptions.contains(value)) return;

    _reminderLeadMinutes = value;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_reminderLeadMinutesKey, value);
  }
}
