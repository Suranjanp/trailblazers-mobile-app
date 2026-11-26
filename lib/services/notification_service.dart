import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

/// Central service for Trailblazer's local notifications.
///
/// Initialize during startup. Request permission separately after the user
/// chooses to enable notifications.
class NotificationService {
  NotificationService._()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _loadTimezone = _deviceTimezone;

  /// Creates an isolated instance for unit tests.
  ///
  /// App screens should continue using [NotificationService.instance].
  /// Creates an isolated instance for unit tests.
  @visibleForTesting
  NotificationService.forTesting({
    required FlutterLocalNotificationsPlugin plugin,
    required Future<String> Function() loadTimezone,
  }) : // Keep public parameter names for test callers.
       // ignore: prefer_initializing_formals
       _plugin = plugin,
       // ignore: prefer_initializing_formals
       _loadTimezone = loadTimezone;

  /// Shared instance used throughout the app.
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin;
  final Future<String> Function() _loadTimezone;

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

  /// Reads the actual device time zone during normal app usage.
  static Future<String> _deviceTimezone() async {
    final deviceTimezone = await FlutterTimezone.getLocalTimezone();
    return deviceTimezone.identifier;
  }

  /// Initializes notifications and configures the local IANA time zone.
  ///
  /// This does not request notification permission or display a notification.
  Future<void> initialize({
    DidReceiveNotificationResponseCallback? onNotificationTap,
  }) async {
    if (_isInitialized) return;

    timezone_data.initializeTimeZones();

    try {
      final identifier = await _loadTimezone();
      tz.setLocalLocation(tz.getLocation(identifier));
    } catch (error) {
      // Stop rather than schedule reminders using an incorrect time zone.
      throw StateError(
        'Trailblazer could not determine the device time zone. '
        'Notification scheduling was not initialized. Details: $error',
      );
    }

    const androidSettings = AndroidInitializationSettings('launcher_icon');

    // Permission prompts remain tied to a user-initiated settings action.
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

  /// Requests notification permission after the user enables alerts.
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

  /// Shows an immediate notification in the selected notification channel.
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

  /// Schedules one event reminder.
  ///
  /// Returns false when the calculated reminder time has already passed.
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

  /// Rebuilds reminders for up to sixty occurrences of one event.
  ///
  /// The complete reserved ID range is cancelled first to remove stale
  /// reminders when an event's repeat pattern changes.
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

  /// Cancels one notification.
  Future<void> cancelNotification(int notificationId) async {
    _ensureInitialized();
    await _plugin.cancel(id: notificationId);
  }

  /// Cancels the sixty reserved reminder IDs belonging to one event.
  Future<void> cancelEventReminderOccurrences(int firstNotificationId) async {
    _ensureInitialized();

    for (var index = 0; index < 60; index++) {
      await _plugin.cancel(id: firstNotificationId + index);
    }
  }

  /// Cancels all scheduled and currently displayed app notifications.
  Future<void> cancelAllNotifications() async {
    _ensureInitialized();
    await _plugin.cancelAll();
  }

  /// Returns notifications currently pending on the device.
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    _ensureInitialized();
    return _plugin.pendingNotificationRequests();
  }

  /// Keeps channel IDs stable so Android retains users' channel preferences.
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

  /// Provides a clear error when a caller skips startup initialization.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'NotificationService has not been initialized. '
        'Call NotificationService.instance.initialize() first.',
      );
    }
  }
}
