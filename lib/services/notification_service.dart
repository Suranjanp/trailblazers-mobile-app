import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// Central service for Trailblazer's local notifications.
///
/// Call [initialize] once during app startup. Ask for notification permission
/// from a user-initiated settings action by calling [requestPermissions].
///
/// This singleton keeps notification setup, scheduling, cancellation, and
/// platform-specific presentation details in one place. Screens should call
/// this service rather than configuring the notification plugin themselves.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Plugin instance used for all local notification operations.
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Android notification channels separate schedule reminders from optional
  // motivational messages so users can manage their behavior independently.
  static const String _scheduleChannelId = 'trailblazer_schedule_reminders';
  static const String _scheduleChannelName = 'Schedule reminders';
  static const String _scheduleChannelDescription =
      'Reminders for events and activities in your Trailblazer schedule.';

  static const String _motivationChannelId = 'trailblazer_motivation';
  static const String _motivationChannelName = 'Motivation';
  static const String _motivationChannelDescription =
      'Optional encouragement and motivation from Trailblazer.';

  // Prevents plugin operations from running before platform initialization
  // and time-zone configuration have completed.
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initializes local notifications and loads the device's IANA time zone.
  ///
  /// This does not request permission or display anything to the user.
  /// The optional callback receives taps on notifications, allowing the app
  /// shell to route the user to the relevant screen or item.
  Future<void> initialize({
    DidReceiveNotificationResponseCallback? onNotificationTap,
  }) async {
    if (_isInitialized) return;

    // The timezone package needs its database loaded before a local location
    // can be selected for scheduling notifications at the correct wall time.
    timezone_data.initializeTimeZones();

    try {
      final deviceTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimezone.identifier));
    } catch (error) {
      // Do not continue with an unknown local zone: scheduled reminders could
      // otherwise appear at an unexpected time for the user.
      throw StateError(
        'Trailblazer could not determine the device time zone. '
        'Notification scheduling was not initialized. Details: $error',
      );
    }

    // Use the app's launcher icon for Android notifications. On Apple
    // platforms, defer permission prompts until the user enables notifications.
    const androidSettings = AndroidInitializationSettings('launcher_icon');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );

    // Mark initialization complete only after the plugin has finished setup.
    _isInitialized = true;
  }

  /// Requests notification permission after the user chooses to enable alerts.
  /// Returns true when permission is granted (or not required on the platform).
  Future<bool> requestPermissions() async {
    _ensureInitialized();

    // Android 13 and later require runtime notification permission. Resolve
    // the Android implementation only when running on that platform.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    }

    // Request alert and sound presentation on iOS. Badge permission is not
    // needed by this app's current notification experience.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      return granted ?? false;
    }

    // Platforms without a permission request in this implementation can
    // proceed without prompting.
    return true;
  }

  /// Shows a notification immediately.
  ///
  /// Use [isMotivation] to place it in the optional motivation channel rather
  /// than the schedule-reminder channel.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool isMotivation = false,
  }) async {
    _ensureInitialized();

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(isMotivation: isMotivation),
      payload: payload,
    );
  }

  /// Schedules one reminder for a calendar event.
  ///
  /// [eventStart] is the event's local date and time. [minutesBefore] controls
  /// how early the reminder appears. Returns false if the reminder time has
  /// already passed and therefore was not scheduled.
  Future<bool> scheduleEventReminder({
    required int notificationId,
    required String title,
    required DateTime eventStart,
    int minutesBefore = 15,
    String? location,
    String? payload,
  }) async {
    _ensureInitialized();

    // Calculate the alert time relative to the event and avoid creating
    // reminders that would need to fire immediately or in the past.
    final reminderTime = eventStart.subtract(Duration(minutes: minutesBefore));
    if (!reminderTime.isAfter(DateTime.now())) return false;

    // Include a location hint when one is available; otherwise use a generic
    // message that does not assume the event has a venue.
    final body = location == null || location.trim().isEmpty
        ? 'Your scheduled event is coming up.'
        : 'Coming up at ${location.trim()}.';

    await _plugin.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(reminderTime, tz.local),
      notificationDetails: _notificationDetails(),
      // Inexact scheduling allows Android to balance timing precision with
      // battery efficiency while permitting delivery during idle periods.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );

    return true;
  }

  /// Schedules reminders for a list of occurrences belonging to one event.
  ///
  /// Pass the future occurrence start times calculated from the event's repeat
  /// settings. Existing reminders in the supplied ID range are cancelled first
  /// so editing an event does not leave its previous reminders behind.
  /// The list is limited to 60 occurrences per call.
  Future<int> scheduleEventReminderOccurrences({
    required int firstNotificationId,
    required String title,
    required List<DateTime> eventStartTimes,
    int minutesBefore = 15,
    String? location,
    String? payloadPrefix,
  }) async {
    _ensureInitialized();

    // Keep the reminder window bounded and deterministic. Each occurrence
    // receives a unique ID based on its position in the supplied list.
    final occurrenceCount = eventStartTimes.length > 60
        ? 60
        : eventStartTimes.length;

    // Clear the complete reserved ID range before rebuilding it. This also
    // removes stale reminders when an event's recurrence pattern is shortened.
    for (var index = 0; index < 60; index++) {
      await _plugin.cancel(id: firstNotificationId + index);
    }

    var scheduledCount = 0;
    for (var index = 0; index < occurrenceCount; index++) {
      final scheduled = await scheduleEventReminder(
        notificationId: firstNotificationId + index,
        title: title,
        eventStart: eventStartTimes[index],
        minutesBefore: minutesBefore,
        location: location,
        payload: payloadPrefix == null ? null : '$payloadPrefix:$index',
      );
      if (scheduled) scheduledCount++;
    }

    // Report only reminders that were actually placed in the future and
    // successfully scheduled by scheduleEventReminder.
    return scheduledCount;
  }

  /// Cancels one notification by its ID.
  Future<void> cancelNotification(int notificationId) async {
    _ensureInitialized();
    await _plugin.cancel(id: notificationId);
  }

  /// Cancels up to 60 occurrence reminders created for one event.
  Future<void> cancelEventReminderOccurrences(int firstNotificationId) async {
    _ensureInitialized();

    // Occurrence IDs occupy the same fixed range used by the scheduling method.
    for (var index = 0; index < 60; index++) {
      await _plugin.cancel(id: firstNotificationId + index);
    }
  }

  /// Cancels all scheduled and currently displayed Trailblazer notifications.
  Future<void> cancelAllNotifications() async {
    _ensureInitialized();
    await _plugin.cancelAll();
  }

  /// Returns the notifications that are currently scheduled and pending.
  ///
  /// This is useful when settings screens need to inspect which reminders
  /// remain queued on the device.
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    _ensureInitialized();
    return _plugin.pendingNotificationRequests();
  }

  /// Builds the platform presentation configuration for the selected channel.
  ///
  /// Schedule reminders use higher Android importance than optional
  /// motivational notifications, while both can present alerts and sound on
  /// iOS. The channel IDs remain stable so Android retains user channel choices.
  NotificationDetails _notificationDetails({bool isMotivation = false}) {
    if (isMotivation) {
      return const NotificationDetails(
        android: AndroidNotificationDetails(
          _motivationChannelId,
          _motivationChannelName,
          channelDescription: _motivationChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );
    }

    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _scheduleChannelId,
        _scheduleChannelName,
        channelDescription: _scheduleChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
  }

  /// Guards public operations that depend on the notification plugin.
  ///
  /// Failing fast with a clear error makes startup-order problems easier to
  /// diagnose than allowing an uninitialized plugin call to fail indirectly.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'NotificationService has not been initialized. '
        'Call NotificationService.instance.initialize() first.',
      );
    }
  }
}
