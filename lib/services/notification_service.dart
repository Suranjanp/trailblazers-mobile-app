import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// Central service for Trailblazer's local notifications.
///
/// Call [initialize] once during app startup. Ask for notification permission
/// from a user-initiated settings action by calling [requestPermissions].
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _scheduleChannelId = 'trailblazer_schedule_reminders';
  static const String _scheduleChannelName = 'Schedule reminders';
  static const String _scheduleChannelDescription =
      'Reminders for events and activities in your Trailblazer schedule.';

  static const String _motivationChannelId = 'trailblazer_motivation';
  static const String _motivationChannelName = 'Motivation';
  static const String _motivationChannelDescription =
      'Optional encouragement and motivation from Trailblazer.';

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initializes local notifications and loads the device's IANA time zone.
  ///
  /// This does not request permission or display anything to the user.
  Future<void> initialize({
    DidReceiveNotificationResponseCallback? onNotificationTap,
  }) async {
    if (_isInitialized) return;

    timezone_data.initializeTimeZones();

    try {
      final deviceTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimezone.identifier));
    } catch (error) {
      throw StateError(
        'Trailblazer could not determine the device time zone. '
        'Notification scheduling was not initialized. Details: $error',
      );
    }

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

    _isInitialized = true;
  }

  /// Requests notification permission after the user chooses to enable alerts.
  /// Returns true when permission is granted (or not required on the platform).
  Future<bool> requestPermissions() async {
    _ensureInitialized();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    }

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

    final reminderTime = eventStart.subtract(Duration(minutes: minutesBefore));
    if (!reminderTime.isAfter(DateTime.now())) return false;

    final body = location == null || location.trim().isEmpty
        ? 'Your scheduled event is coming up.'
        : 'Coming up at ${location.trim()}.';

    await _plugin.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(reminderTime, tz.local),
      notificationDetails: _notificationDetails(),
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

    final occurrenceCount = eventStartTimes.length > 60
        ? 60
        : eventStartTimes.length;

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
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    _ensureInitialized();
    return _plugin.pendingNotificationRequests();
  }

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

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'NotificationService has not been initialized. '
        'Call NotificationService.instance.initialize() first.',
      );
    }
  }
}
