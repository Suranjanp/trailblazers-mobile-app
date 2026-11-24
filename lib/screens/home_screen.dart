import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/health_connect_service.dart';

import '../services/schedule_service.dart';
import '../services/dashboard_calendar_cache.dart';
import '../services/points_service.dart';

/// Main dashboard shown on the Home tab.
///
/// It brings together the user's upcoming schedule, wellness measurements,
/// weekly workout summary, to-do items, and Trailblazer points. Detailed data
/// is loaded from the app's existing services and the signed-in user's
/// Firestore collections.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenSchedule});

  /// Optional callback used by the app shell to navigate to the Schedule tab.
  final VoidCallback? onOpenSchedule;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Short weekday codes match the format used by saved training-day settings.
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  // Full weekday names are used for headings and event date labels.
  static const List<String> _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  // Local schedule entries are cached here after loading from ScheduleService.
  List<Map<String, dynamic>> _schedule = [];
  bool _scheduleLoading = true;
  String? _scheduleError;

  // The dashboard clock is refreshed every minute so countdowns stay current.
  DateTime _now = DateTime.now();
  Timer? _minuteTimer;

  // Index of the event currently shown in the Coming Up carousel.
  int _eventIndex = 0;

  // Health Connect provides step totals on supported Android devices.
  final HealthConnectService _healthService = HealthConnectService();
  int? _todaySteps;
  int _waterIntakeMl = 0;
  double _sleepHours = 0;
  int _weeklyWorkoutCount = 0;
  int _weeklyWorkoutMinutes = 0;
  bool _wellnessLoading = true;
  bool _healthConnectReady = false;
  bool _healthConnectConnected = false;

  // Points dashboard state: lifetime balance, period reports, and recent awards.
  int _lifetimePoints = 0;
  PointsReport? _dailyPointsReport;
  PointsReport? _weeklyPointsReport;
  PointsReport? _monthlyPointsReport;
  String _pointsPeriod = 'week';
  bool _pointsLoading = true;
  String? _pointsError;
  List<Map<String, dynamic>> _recentPointActivities = [];

  // Google Calendar events are supplied through a shared cache populated by
  // the Schedule screen, keeping this dashboard from performing another sync.
  List<Map<String, dynamic>> get _googleEvents =>
      DashboardCalendarCache.instance.events;

  // All user-specific Firestore reads are scoped to the current account.
  User? get _user => FirebaseAuth.instance.currentUser;

  /// Reference to the user's current fitness profile, if signed in.
  ///
  /// The profile contains training-day preferences used for the workout/rest
  /// note displayed beside the date in the dashboard heading.
  DocumentReference<Map<String, dynamic>>? get _fitnessProfile {
    final user = _user;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('fitness_profile')
        .doc('current');
  }

  @override
  void initState() {
    super.initState();

    // Subscribe to shared data/preferences before loading the dashboard panels.
    DashboardCalendarCache.instance.addListener(_onCalendarChanged);
    AppSettings.instance.addListener(_onAppSettingsChanged);
    _loadSchedule();
    _loadWellnessData();
    _loadPointsData();
    _initializeHomeHealthConnect();

    // Update countdown labels and refresh local schedule data once per minute.
    // This also picks up changes made on the Schedule page while Home is open.
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _loadSchedule(silent: true);
    });
  }

  // Rebuild labels that depend on the user's measurement or appearance settings.
  void _onAppSettingsChanged() {
    if (mounted) setState(() {});
  }

  // Reset the carousel when the shared Google Calendar event list changes.
  void _onCalendarChanged() {
    if (!mounted) return;
    setState(() => _eventIndex = 0);
  }

  @override
  void dispose() {
    // Remove listeners and stop the periodic timer when leaving the dashboard.
    DashboardCalendarCache.instance.removeListener(_onCalendarChanged);
    AppSettings.instance.removeListener(_onAppSettingsChanged);
    _minuteTimer?.cancel();
    super.dispose();
  }

  /// Loads local schedule entries and converts them to mutable map copies.
  ///
  /// [silent] is used by the periodic refresh so a background refresh failure
  /// does not replace the dashboard with an error message unnecessarily.
  Future<void> _loadSchedule({bool silent = false}) async {
    try {
      final entries = await ScheduleService.loadEntries();
      if (!mounted) return;
      setState(() {
        _schedule = entries
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
        _scheduleLoading = false;
        _scheduleError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scheduleLoading = false;
        if (!silent) _scheduleError = 'Your schedule could not be loaded.';
      });
    }
  }

  // Normalize a date to midnight before comparing calendar days.
  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  // Stable local date key used when reading health logs and matching events.
  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Loads today's hydration/sleep values and the current week's workouts.
  ///
  /// Workout documents are filtered to completed sessions. Their durations are
  /// added together and converted from seconds to whole minutes for display.
  Future<void> _loadWellnessData() async {
    final user = _user;
    if (user == null) {
      if (mounted) setState(() => _wellnessLoading = false);
      return;
    }

    final today = _dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    try {
      final root = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final results = await Future.wait([
        root.collection('health_logs').doc(_dateKey(today)).get(),
        root.collection('workout_sessions')
            .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
            .orderBy('startedAt', descending: true)
            .limit(100)
            .get(),
      ]);
      if (!mounted) return;
      final health = (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ?? <String, dynamic>{};
      final workouts = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final completed = workouts.docs.where((doc) => doc.data()['status'] == 'completed').toList();
      final seconds = completed.fold<int>(0, (total, doc) =>
          total + ((doc.data()['durationSeconds'] as num?)?.toInt() ?? 0));
      setState(() {
        _waterIntakeMl = (health['waterIntake'] as num?)?.toInt() ?? 0;
        _sleepHours = (health['sleepHours'] as num?)?.toDouble() ?? 0;
        _weeklyWorkoutCount = completed.length;
        _weeklyWorkoutMinutes = seconds ~/ 60;
        _wellnessLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _wellnessLoading = false);
    }
  }

  /// Loads lifetime points and the daily, weekly, and monthly reports.
  ///
  /// Recent transactions are fetched separately so a failure in that optional
  /// list does not prevent the main balance and reports from being displayed.
  Future<void> _loadPointsData() async {
    if (mounted) {
      setState(() {
        _pointsLoading = true;
        _pointsError = null;
      });
    }

    try {
      final user = _user;
      if (user == null) {
        throw StateError('No signed-in Firebase user was found.');
      }

      // Load the balance and reports independently of the optional recent
      // activity list. A failure in that list must not hide a valid balance.
      final results = await Future.wait<Object>([
        PointsService.instance.getTotalPoints(),
        PointsService.instance.getDailyReport(),
        PointsService.instance.getWeeklyReport(),
        PointsService.instance.getMonthlyReport(),
      ]);

      var recentActivities = <Map<String, dynamic>>[];
      try {
        final recentSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('points_transactions')
            .orderBy('earnedAt', descending: true)
            .limit(3)
            .get();
        recentActivities = recentSnapshot.docs
            .map((doc) => doc.data())
            .toList();
      } catch (error, stackTrace) {
        debugPrint('Trailblazer recent points could not load: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      if (!mounted) return;
      setState(() {
        _lifetimePoints = results[0] as int;
        _dailyPointsReport = results[1] as PointsReport;
        _weeklyPointsReport = results[2] as PointsReport;
        _monthlyPointsReport = results[3] as PointsReport;
        _recentPointActivities = recentActivities;
        _pointsLoading = false;
        _pointsError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Trailblazer points dashboard failed to load: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _pointsLoading = false;
        _pointsError = kDebugMode
            ? 'Points information could not be loaded: $error'
            : 'Points information could not be loaded.';
      });
    }
  }

  // Select the report matching the Day/Week/Month control in the points card.
  PointsReport? get _selectedPointsReport {
    switch (_pointsPeriod) {
      case 'day':
        return _dailyPointsReport;
      case 'month':
        return _monthlyPointsReport;
      default:
        return _weeklyPointsReport;
    }
  }

  // Human-readable label for the currently selected points reporting period.
  String _pointsPeriodLabel() {
    switch (_pointsPeriod) {
      case 'day':
        return 'Today';
      case 'month':
        return 'This month';
      default:
        return 'This week';
    }
  }

  // Delegate category naming to PointsService so labels stay consistent app-wide.
  String _pointsCategoryLabel(String category) =>
      PointsService.instance.categoryLabel(category);

  // Lifetime point thresholds for ranks. The first threshold advances the user
  // from Newcomer to Explorer; each later threshold unlocks the next title.
  static const List<int> _pointsMilestones = [
    500,
    1500,
    3500,
    7500,
    15000,
    30000,
    50000,
    80000,
    120000,
    180000,
    260000,
    360000,
    500000,
    700000,
  ];

  // Rank names align by index with the milestone list, plus the starting rank.
  static const List<String> _pointsRankTitles = [
    'Newcomer',
    'Explorer',
    'Adventurer',
    'Pathfinder',
    'Achiever',
    'Champion',
    'Elite',
    'Master',
    'Legend',
    'Trailblazer',
    'Vanguard',
    'Pioneer',
    'Summit Master',
    'Summit Legend',
    'Grand Trailblazer',
  ];

  // Find the first threshold the user has not yet reached.
  int _nextPointsMilestone(int points) {
    for (final milestone in _pointsMilestones) {
      if (points < milestone) return milestone;
    }
    return _pointsMilestones.last;
  }

  // Find the lower bound of the current rank to calculate progress to the next.
  int _previousPointsMilestone(int nextMilestone) {
    final index = _pointsMilestones.indexOf(nextMilestone);
    if (index <= 0) return 0;
    return _pointsMilestones[index - 1];
  }

  // Resolve the highest rank whose threshold has been met by the point balance.
  String _pointsLevel(int points) {
    for (var index = _pointsMilestones.length - 1; index >= 0; index--) {
      if (points >= _pointsMilestones[index]) {
        return _pointsRankTitles[index + 1];
      }
    }
    return _pointsRankTitles.first;
  }

  // Label the milestone associated with the user's current rank.
  String _pointsMilestoneTitle(int points) {
    for (var index = _pointsMilestones.length - 1; index >= 0; index--) {
      if (points >= _pointsMilestones[index]) {
        return '${_pointsMilestones[index]}-point milestone';
      }
    }
    return 'First rank ahead';
  }

  /// Builds the Trailblazer Points card on the Home dashboard.
  ///
  /// It combines lifetime rank progress with a selectable period report,
  /// category breakdown bars, and the three most recent point transactions.
  Widget _buildPointsDashboardCard() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final report = _selectedPointsReport;
    final nextMilestone = _nextPointsMilestone(_lifetimePoints);
    final previousMilestone = _previousPointsMilestone(nextMilestone);
    final hasReachedTopRank = _lifetimePoints >= _pointsMilestones.last;
    final progress = hasReachedTopRank
        ? 1.0
        : ((_lifetimePoints - previousMilestone) /
            (nextMilestone - previousMilestone)).clamp(0.0, 1.0).toDouble();

    // Sort categories from highest to lowest so the strongest point sources
    // appear first, and scale all category bars against the largest category.
    final categories = report?.pointsByCategory.entries.toList()
      ?..sort((a, b) => b.value.compareTo(a.value));
    final maxCategoryPoints = categories == null || categories.isEmpty
        ? 1
        : categories.first.value;

    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon, section title, current rank, and lifetime point total.
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.emoji_events_rounded, color: colors.primary),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trailblazer Points',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(_pointsLevel(_lifetimePoints),
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (!_pointsLoading)
                  Text('$_lifetimePoints pts',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (_pointsLoading)
              const LinearProgressIndicator()
            else if (_pointsError != null)
              Row(
                children: [
                  Expanded(child: Text(_pointsError!,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
                  TextButton(onPressed: _loadPointsData, child: const Text('Retry')),
                ],
              )
            else ...[
              // Show the current milestone and progress toward the next rank.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_pointsMilestoneTitle(_lifetimePoints),
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(hasReachedTopRank
                      ? 'Top rank achieved'
                      : 'Next: $nextMilestone pts',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 14),

              // Switch the activity summary between daily, weekly, and monthly.
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text('Day')),
                  ButtonSegment(value: 'week', label: Text('Week')),
                  ButtonSegment(value: 'month', label: Text('Month')),
                ],
                selected: {_pointsPeriod},
                onSelectionChanged: (selection) {
                  setState(() => _pointsPeriod = selection.first);
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
                ),
              ),
              const SizedBox(height: 12),

              // Period total and activity count are displayed side by side.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_pointsPeriodLabel(),
                            style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text('${report?.totalPoints ?? 0} points',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 38, color: colors.outlineVariant),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Activities',
                            style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text('${report?.activityCount ?? 0}',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Category bars compare how many points came from each activity.
              if (categories != null && categories.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Earned by activity',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 9),
                ...categories.map((entry) {
                  final ratio = entry.value / maxCategoryPoints;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(_pointsCategoryLabel(entry.key),
                              style: theme.textTheme.bodySmall)),
                            Text('${entry.value} pts',
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 6,
                            backgroundColor: colors.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ] else ...[
                const SizedBox(height: 12),
                Text('Complete activities to start building your points history.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.stars_rounded, color: colors.primary, size: 18),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _lifetimePoints >= 100
                          ? 'Latest milestone: ${_pointsMilestoneTitle(_lifetimePoints)}'
                          : 'Your first achievement unlocks at 100 points.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),

              // The most recent awards help users understand where new points came from.
              if (_recentPointActivities.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(color: colors.outlineVariant.withValues(alpha: 0.6)),
                Text('Recent achievements',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                ..._recentPointActivities.map((activity) {
                  final title = activity['title']?.toString() ?? 'Completed activity';
                  final points = (activity['points'] as num?)?.toInt() ?? 0;
                  final earnedAt = activity['earnedAt'];
                  final date = earnedAt is Timestamp ? earnedAt.toDate() : null;
                  final dateLabel = date == null
                      ? ''
                      : ' · ${date.month}/${date.day}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                          color: colors.primary, size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text('$title$dateLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                        ),
                        Text('+$points',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Prepares Health Connect on Android and checks whether read access exists.
  ///
  /// Other platforms mark initialization complete without attempting to use
  /// the Android-only integration. If access is available, today's steps load.
  Future<void> _initializeHomeHealthConnect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _healthConnectReady = true);
      return;
    }
    try {
      await _healthService.initialize();
      final available = await _healthService.isAvailable();
      final hasAccess = available && await _healthService.hasReadAccess();
      if (!mounted) return;
      setState(() {
        _healthConnectReady = true;
        _healthConnectConnected = hasAccess;
      });
      if (hasAccess) await _refreshHomeSteps();
    } catch (_) {
      if (mounted) setState(() => _healthConnectReady = true);
    }
  }

  // Read the current day's step metric and update the small wellness summary.
  Future<void> _refreshHomeSteps() async {
    try {
      final metrics = await _healthService.readToday();
      if (!mounted) return;
      setState(() => _todaySteps = metrics.steps);
    } catch (_) {
      if (mounted) setState(() => _healthConnectConnected = false);
    }
  }

  // Display the stored milliliter amount in the currently selected water unit.
  String _waterDisplay() {
    if (AppSettings.instance.isMetric) return '$_waterIntakeMl ml';
    return '${(_waterIntakeMl / 29.5735).round()} fl oz';
  }

  /// Extracts the weekday codes from a schedule entry.
  ///
  /// Newer entries use a list of days; the single `day` field is retained as a
  /// fallback for older saved schedule records.
  List<String> _daysForEntry(Map<String, dynamic> entry) {
    final rawDays = entry['days'];
    if (rawDays is List && rawDays.isNotEmpty) {
      return rawDays.map((day) => day.toString()).where(_weekdays.contains).toSet().toList();
    }
    final legacyDay = entry['day']?.toString();
    if (legacyDay != null && _weekdays.contains(legacyDay)) return [legacyDay];
    return [];
  }

  /// Converts an HH:mm value to minutes after midnight.
  ///
  /// Returning -1 for malformed values lets callers identify invalid times
  /// without throwing while building the dashboard's event list.
  int _minutesFromTime(Object? value) {
    if (value == null) return -1;
    final parts = value.toString().split(':');
    if (parts.length != 2) return -1;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return -1;
    }
    return hour * 60 + minute;
  }

  // Resolve an event's start DateTime for a particular occurrence date.
  DateTime? _eventStart(Map<String, dynamic> entry, DateTime date) {
    if (entry['allDay'] == true) return date;
    final minutes = _minutesFromTime(entry['startTime']);
    if (minutes < 0) return null;
    return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
  }

  // Resolve an event's end DateTime; all-day events end at the next midnight.
  DateTime? _eventEnd(Map<String, dynamic> entry, DateTime date) {
    if (entry['allDay'] == true) return date.add(const Duration(days: 1));
    final minutes = _minutesFromTime(entry['endTime']);
    if (minutes < 0) return null;
    return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
  }

  /// Determines whether a saved schedule entry occurs on [date].
  ///
  /// To-do items are handled in their own section. Other entries may repeat
  /// yearly, weekly, or occur once on their saved date.
  bool _entryOccursOn(Map<String, dynamic> entry, DateTime date) {
    if (entry['entryType'] == 'todo') return false;

    final savedDate = DateTime.tryParse(entry['date']?.toString() ?? '');
    if (entry['repeatYearly'] == true) {
      return savedDate != null && savedDate.month == date.month && savedDate.day == date.day;
    }
    if (entry['repeatWeekly'] != false) {
      return _daysForEntry(entry).contains(_weekdays[date.weekday - 1]);
    }
    return savedDate != null && _dateOnly(savedDate) == _dateOnly(date);
  }

  /// Collects and sorts upcoming local and Google Calendar events.
  ///
  /// Local repeating entries are checked across the next 14 days. Past events
  /// are omitted unless they are still in progress. Google Calendar entries
  /// are read-only and are obtained from [DashboardCalendarCache].
  List<_HomeEvent> _upcomingEvents() {
    final events = <_HomeEvent>[];
    final today = _dateOnly(_now);

    // The Schedule page supports weekly, yearly, and one-time local entries.
    // Check the next two weeks so recurring entries can appear naturally.
    for (var offset = 0; offset < 14; offset++) {
      final date = today.add(Duration(days: offset));
      for (final entry in _schedule) {
        if (!_entryOccursOn(entry, date)) continue;
        final start = _eventStart(entry, date);
        if (start == null) continue;
        final end = _eventEnd(entry, date);
        if (start.isBefore(_now) && (end == null || !end.isAfter(_now))) continue;
        events.add(_HomeEvent(entry: entry, startsAt: start, endsAt: end));
      }
    }

    // Google Calendar entries are read-only and shared from ScheduleScreen.
    for (final entry in _googleEvents) {
      if (entry['externalGoogle'] != true) continue;
      final date = DateTime.tryParse(entry['date']?.toString() ?? '');
      if (date == null) continue;
      final start = _eventStart(entry, date);
      if (start == null) continue;
      final end = _eventEnd(entry, date);
      if (start.isBefore(_now) && (end == null || !end.isAfter(_now))) continue;
      events.add(_HomeEvent(entry: entry, startsAt: start, endsAt: end));
    }

    events.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return events;
  }

  /// Returns up to two incomplete to-do items scheduled for today.
  ///
  /// Higher-importance tasks are sorted first so the dashboard highlights the
  /// tasks the user has prioritized most highly.
  List<Map<String, dynamic>> _todayTodos() {
    final today = _dateOnly(_now);
    final todos = _schedule.where((entry) {
      if (entry['entryType'] != 'todo' || entry['completed'] == true) return false;
      final date = DateTime.tryParse(entry['date']?.toString() ?? '');
      return date != null && _dateOnly(date) == today;
    }).toList();
    todos.sort((a, b) {
      final aImportance = (a['importance'] as num?)?.toInt() ?? 1;
      final bImportance = (b['importance'] as num?)?.toInt() ?? 1;
      return bImportance.compareTo(aImportance);
    });
    return todos.take(2).toList();
  }

  /// Marks a dashboard to-do as complete, saves it, and awards its points.
  ///
  /// The task's persistent ID is passed to PointsService as the source ID.
  /// This matches the Schedule screen's award key and prevents duplicate
  /// rewards if the same task is completed from either screen.
  Future<void> _toggleTodo(Map<String, dynamic> todo) async {
    final index = _schedule.indexOf(todo);
    if (index < 0 || todo['completed'] == true) return;

    // Work on copied maps so the current in-memory list is not mutated until
    // the ScheduleService write has succeeded.
    final updated = _schedule
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    final updatedTodo = updated[index];
    updatedTodo['completed'] = true;

    // Use the same permanent task ID as the Schedule screen so completing a
    // task from either location can never create a second reward.
    var sourceId = updatedTodo['id']?.toString().trim() ?? '';
    if (sourceId.isEmpty) {
      sourceId = 'todo_${DateTime.now().microsecondsSinceEpoch}';
      updatedTodo['id'] = sourceId;
    }

    try {
      await ScheduleService.saveEntries(updated);
      if (!mounted) return;
      setState(() => _schedule = updated);

      // Clamp legacy or malformed importance values to the supported 1-5 range.
      final rawImportance =
          (updatedTodo['importance'] as num?)?.toInt() ?? 1;
      final importance = rawImportance.clamp(1, 5).toInt();
      try {
        final result = await PointsService.instance.awardActivity(
          type: PointsActivityType.todo,
          sourceId: sourceId,
          title: updatedTodo['name']?.toString() ?? 'To-Do task',
          importance: importance,
          metadata: <String, dynamic>{
            'completedAt': DateTime.now().toIso8601String(),
          },
        );

        if (!mounted) return;
        if (result?.awarded == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Task completed! You earned ${result!.points} points.'),
            ),
          );
        } else if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task completed, but no signed-in account could receive points.')),
          );
        }
        // Refresh the dashboard balance and reports after the award attempt.
        await _loadPointsData();
      } catch (error, stackTrace) {
        debugPrint('Trailblazer To-Do points award failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kDebugMode
                ? 'Task completed, but points could not sync: $error'
                : 'Task completed, but points could not sync. Please try again later.'),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Trailblazer To-Do save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update that task.')),
      );
    }
  }

  // Select a greeting based on the current local hour.
  String _greeting() {
    if (_now.hour < 12) return 'Good morning';
    if (_now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Creates a compact countdown label for an upcoming event.
  String _countdown(DateTime startsAt) {
    final difference = startsAt.difference(_now);
    if (difference.inSeconds <= 0) return 'Starting now';
    final totalMinutes = difference.inMinutes;
    if (totalMinutes < 1) return 'Starting in less than a minute';
    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;
    if (days > 0) return 'In ${days}d ${hours}h';
    if (hours > 0) return 'In ${hours}h ${minutes}m';
    return 'In ${minutes}m';
  }

  // Return either the all-day label or the localized start time for an event.
  String _eventTime(_HomeEvent event) {
    if (event.entry['allDay'] == true) return 'All day';
    return TimeOfDay.fromDateTime(event.startsAt).format(context);
  }

  // Use Today/Tomorrow for nearby dates and a weekday/date for later events.
  String _eventDay(DateTime date) {
    if (_dateOnly(date) == _dateOnly(_now)) return 'Today';
    if (_dateOnly(date) == _dateOnly(_now.add(const Duration(days: 1)))) return 'Tomorrow';
    return '${_weekdayNames[date.weekday - 1]} · ${date.month}/${date.day}';
  }

  /// Pulls the dashboard's main data sets again after a user refresh gesture.
  Future<void> _refresh() async {
    setState(() {
      _now = DateTime.now();
      _scheduleLoading = true;
    });
    await Future.wait([
      _loadSchedule(),
      _loadWellnessData(),
      _loadPointsData(),
    ]);
  }

  /// Builds the complete scrollable Home dashboard.
  ///
  /// The header includes the current date and training/rest-day note. The page
  /// then presents upcoming events, wellness, points, today's tasks, and a
  /// compact weekly fitness summary.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = _now;
    final events = _upcomingEvents().take(3).toList();
    if (_eventIndex >= events.length) _eventIndex = 0;
    final todos = _todayTodos();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          // Greeting, dashboard title, date, and training/rest-day indicator.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting().toUpperCase(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Your day at a glance', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${_weekdayNames[today.weekday - 1]}, ${_monthName(today.month)} ${today.day}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 9),
                        _buildWorkoutDayNote(),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh dashboard',
                onPressed: _scheduleLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // The next event panel is the first major dashboard content section.
          _buildComingUpPanel(events),
          const SizedBox(height: 14),
          _sectionHeading(context, 'Wellness at a glance', Icons.favorite_outline_rounded),
          const SizedBox(height: 8),
          _buildWellnessStats(),
          const SizedBox(height: 16),
          _buildPointsDashboardCard(),

          // Show a short prioritized list only when there are incomplete tasks.
          if (_todayTodos().isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeading(context, 'Today’s to-do', Icons.checklist_rounded),
            const SizedBox(height: 8),
            ...todos.map(_buildTodoCard),
          ],
          const SizedBox(height: 12),
          _buildWeeklyFitnessHighlight(),
          const SizedBox(height: 16),

          // Closing message keeps the dashboard's wellness theme consistent.
          Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.explore_outlined, color: colors.primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Move well. Study well. Play well. Rest well.',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the three compact wellness values: steps, water, and sleep.
  Widget _buildWellnessStats() {
    // Step availability has separate labels for initialization, connection,
    // and a successful read so the dashboard does not imply missing data is 0.
    final stepsValue = _todaySteps == null
        ? (_healthConnectReady
            ? (_healthConnectConnected ? '—' : 'Connect in Fitness')
            : '…')
        : _todaySteps!.toString();
    return Row(
      children: [
        Expanded(child: _wellnessStatCard(
          icon: Icons.directions_walk_rounded,
          label: 'Steps',
          value: stepsValue,
          accent: const Color(0xFF287A9B),
        )),
        const SizedBox(width: 8),
        Expanded(child: _wellnessStatCard(
          icon: Icons.water_drop_outlined,
          label: 'Water',
          value: _wellnessLoading ? '…' : _waterDisplay(),
          accent: const Color(0xFF2686B8),
        )),
        const SizedBox(width: 8),
        Expanded(child: _wellnessStatCard(
          icon: Icons.bedtime_outlined,
          label: 'Sleep',
          value: _wellnessLoading ? '…' : (_sleepHours > 0 ? '${_sleepHours.toStringAsFixed(1)} h' : '—'),
          accent: const Color(0xFF7866A8),
        )),
      ],
    );
  }

  /// Reusable visual tile for one wellness metric.
  Widget _wellnessStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 8),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Summarizes the number and total duration of completed workouts this week.
  Widget _buildWeeklyFitnessHighlight() {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: colors.primary, size: 24),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This week in fitness', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(
                    _wellnessLoading
                        ? 'Loading your activity…'
                        : '$_weeklyWorkoutCount completed ${_weeklyWorkoutCount == 1 ? 'workout' : 'workouts'} · $_weeklyWorkoutMinutes min total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Streams the fitness profile and displays whether today is a training day.
  ///
  /// If no profile exists yet, the default training schedule is Monday,
  /// Wednesday, and Friday. The note is intentionally compact beside the date.
  Widget _buildWorkoutDayNote() {
    final profileRef = _fitnessProfile;
    if (profileRef == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)) {
          return const SizedBox.shrink();
        }

        final profile = snapshot.data?.data() ?? <String, dynamic>{};
        final rawDays = profile['trainingDays'];
        final trainingDays = rawDays is List
            ? rawDays.map((day) => day.toString()).toSet()
            : <String>{'Mon', 'Wed', 'Fri'};
        final todayCode = _weekdays[_now.weekday - 1];
        final isWorkoutDay = trainingDays.contains(todayCode);
        final colors = Theme.of(context).colorScheme;
        final background = isWorkoutDay
            ? colors.primaryContainer
            : colors.surfaceContainerHighest;
        final foreground = isWorkoutDay
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isWorkoutDay
                    ? Icons.fitness_center_rounded
                    : Icons.self_improvement_rounded,
                size: 13,
                color: foreground,
              ),
              const SizedBox(width: 5),
              Text(
                isWorkoutDay ? 'Workout day' : 'Rest day',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds the outer Coming Up panel and handles loading/empty/error states.
  Widget _buildComingUpPanel(List<_HomeEvent> events) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_outlined, color: colors.primary, size: 21),
              const SizedBox(width: 9),
              Text(
                'Coming up',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_scheduleLoading && _schedule.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: CircularProgressIndicator(color: colors.primary),
              ),
            )
          else if (_scheduleError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Your schedule could not be loaded.'),
                  ),
                  TextButton(onPressed: _refresh, child: const Text('Try again')),
                ],
              ),
            )
          else if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text(
                'Nothing coming up on your schedule. Enjoy the open time!',
              ),
            )
          else
            _buildEventCarousel(events),
        ],
      ),
    );
  }

  /// Displays one upcoming event at a time with stable previous/next controls.
  Widget _buildEventCarousel(List<_HomeEvent> events) {
    final colors = Theme.of(context).colorScheme;
    final hasPrevious = _eventIndex > 0;
    final hasNext = _eventIndex < events.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEventCard(events[_eventIndex]),
        const SizedBox(height: 5),
        Row(
          children: [
            // Keep the left control's space when hidden so the index does not shift.
            if (hasPrevious)
              IconButton(
                tooltip: 'Previous event',
                onPressed: () => setState(() => _eventIndex--),
                icon: const Icon(Icons.chevron_left_rounded),
                color: colors.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              )
            else
              const SizedBox(width: 32, height: 36),
            Text(
              '${_eventIndex + 1} of ${events.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasNext)
              IconButton(
                tooltip: 'Next event',
                onPressed: () => setState(() => _eventIndex++),
                icon: const Icon(Icons.chevron_right_rounded),
                color: colors.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onOpenSchedule,
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              icon: const Icon(Icons.calendar_month_outlined, size: 17),
              label: const Text('View full Schedule'),
            ),
          ],
        ),
      ],
    );
  }

  /// Shows the event title, date/time, optional location, and countdown status.
  Widget _buildEventCard(_HomeEvent event) {
    final colors = Theme.of(context).colorScheme;
    final name = event.entry['name']?.toString().trim();
    final location = event.entry['location']?.toString().trim() ?? '';
    final isGoogle = event.entry['externalGoogle'] == true;
    final inProgress = event.startsAt.isBefore(_now) && (event.endsAt?.isAfter(_now) ?? false);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name == null || name.isEmpty ? 'Untitled event' : name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    )),
                  const SizedBox(height: 3),
                  Text(
                    '${_eventDay(event.startsAt)} · ${_eventTime(event)}${location.isEmpty ? '' : ' · $location'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (isGoogle)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        event.entry['googleCalendarName']?.toString() ?? 'Google Calendar',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  inProgress ? 'Happening now' : _countdown(event.startsAt),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (event.endsAt != null && !inProgress)
                  Text('Ends ${TimeOfDay.fromDateTime(event.endsAt!).format(context)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ],
        ),
    );
  }

  /// Builds a single incomplete to-do tile with its importance indicator.
  Widget _buildTodoCard(Map<String, dynamic> todo) {
    final colors = Theme.of(context).colorScheme;
    final importance = (todo['importance'] as num?)?.toInt() ?? 1;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 7),
      color: colors.surfaceContainerLow,
      child: CheckboxListTile(
        value: false,
        onChanged: (_) => _toggleTodo(todo),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        title: Text(todo['name']?.toString() ?? 'Task', style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('Importance $importance / 5'),
        secondary: Icon(
          importance >= 4 ? Icons.priority_high_rounded : Icons.flag_outlined,
          color: importance >= 4 ? colors.error : colors.onSurfaceVariant,
          size: 20,
        ),
      ),
    );
  }

  // Shared heading row used above dashboard sections.
  Widget _sectionHeading(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // Convert a month number to its full display name for the dashboard date.
  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }
}

/// Normalized event model used by the Coming Up panel.
///
/// The original entry map is retained for optional fields such as location,
/// all-day status, and Google Calendar source details; parsed DateTimes are
/// stored separately to simplify sorting and countdown calculations.
class _HomeEvent {
  const _HomeEvent({required this.entry, required this.startsAt, this.endsAt});

  final Map<String, dynamic> entry;
  final DateTime startsAt;
  final DateTime? endsAt;
}
