import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/health_connect_service.dart';

import '../services/schedule_service.dart';
import '../services/dashboard_calendar_cache.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenSchedule});

  final VoidCallback? onOpenSchedule;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<String> _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  List<Map<String, dynamic>> _schedule = [];
  bool _scheduleLoading = true;
  String? _scheduleError;
  DateTime _now = DateTime.now();
  Timer? _minuteTimer;
  int _eventIndex = 0;
  final HealthConnectService _healthService = HealthConnectService();
  int? _todaySteps;
  int _waterIntakeMl = 0;
  double _sleepHours = 0;
  int _weeklyWorkoutCount = 0;
  int _weeklyWorkoutMinutes = 0;
  bool _wellnessLoading = true;
  bool _healthConnectReady = false;
  bool _healthConnectConnected = false;

  List<Map<String, dynamic>> get _googleEvents =>
      DashboardCalendarCache.instance.events;

  User? get _user => FirebaseAuth.instance.currentUser;

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
    DashboardCalendarCache.instance.addListener(_onCalendarChanged);
    AppSettings.instance.addListener(_onAppSettingsChanged);
    _loadSchedule();
    _loadWellnessData();
    _initializeHomeHealthConnect();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      // Schedule entries are stored locally. A lightweight refresh keeps this
      // dashboard current after edits made on the Schedule page.
      _loadSchedule(silent: true);
    });
  }

  void _onAppSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onCalendarChanged() {
    if (!mounted) return;
    setState(() => _eventIndex = 0);
  }

  @override
  void dispose() {
    DashboardCalendarCache.instance.removeListener(_onCalendarChanged);
    AppSettings.instance.removeListener(_onAppSettingsChanged);
    _minuteTimer?.cancel();
    super.dispose();
  }

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

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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

  Future<void> _refreshHomeSteps() async {
    try {
      final metrics = await _healthService.readToday();
      if (!mounted) return;
      setState(() => _todaySteps = metrics.steps);
    } catch (_) {
      if (mounted) setState(() => _healthConnectConnected = false);
    }
  }

  String _waterDisplay() {
    if (AppSettings.instance.isMetric) return '$_waterIntakeMl ml';
    return '${(_waterIntakeMl / 29.5735).round()} fl oz';
  }


  List<String> _daysForEntry(Map<String, dynamic> entry) {
    final rawDays = entry['days'];
    if (rawDays is List && rawDays.isNotEmpty) {
      return rawDays.map((day) => day.toString()).where(_weekdays.contains).toSet().toList();
    }
    final legacyDay = entry['day']?.toString();
    if (legacyDay != null && _weekdays.contains(legacyDay)) return [legacyDay];
    return [];
  }

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

  DateTime? _eventStart(Map<String, dynamic> entry, DateTime date) {
    if (entry['allDay'] == true) return date;
    final minutes = _minutesFromTime(entry['startTime']);
    if (minutes < 0) return null;
    return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
  }

  DateTime? _eventEnd(Map<String, dynamic> entry, DateTime date) {
    if (entry['allDay'] == true) return date.add(const Duration(days: 1));
    final minutes = _minutesFromTime(entry['endTime']);
    if (minutes < 0) return null;
    return DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);
  }

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

  Future<void> _toggleTodo(Map<String, dynamic> todo) async {
    final index = _schedule.indexOf(todo);
    if (index < 0) return;
    final updated = _schedule.map((entry) => Map<String, dynamic>.from(entry)).toList();
    updated[index]['completed'] = true;
    try {
      await ScheduleService.saveEntries(updated);
      if (!mounted) return;
      setState(() => _schedule = updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update that task.')),
      );
    }
  }

  String _greeting() {
    if (_now.hour < 12) return 'Good morning';
    if (_now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

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

  String _eventTime(_HomeEvent event) {
    if (event.entry['allDay'] == true) return 'All day';
    return TimeOfDay.fromDateTime(event.startsAt).format(context);
  }

  String _eventDay(DateTime date) {
    if (_dateOnly(date) == _dateOnly(_now)) return 'Today';
    if (_dateOnly(date) == _dateOnly(_now.add(const Duration(days: 1)))) return 'Tomorrow';
    return '${_weekdayNames[date.weekday - 1]} · ${date.month}/${date.day}';
  }

  Future<void> _refresh() async {
    setState(() {
      _now = DateTime.now();
      _scheduleLoading = true;
    });
    await _loadSchedule();
  }

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
                    Text(
                      '${_weekdayNames[today.weekday - 1]}, ${_monthName(today.month)} ${today.day}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
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
          _buildComingUpPanel(events),
          const SizedBox(height: 14),
          _sectionHeading(context, 'Wellness at a glance', Icons.favorite_outline_rounded),
          const SizedBox(height: 8),
          _buildWellnessStats(),
          if (_todayTodos().isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeading(context, 'Today’s to-do', Icons.checklist_rounded),
            const SizedBox(height: 8),
            ...todos.map(_buildTodoCard),
          ],
          const SizedBox(height: 12),
          _buildWorkoutStatus(),
          const SizedBox(height: 10),
          _buildWeeklyFitnessHighlight(),
          const SizedBox(height: 16),
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


  Widget _buildWellnessStats() {
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

  Widget _buildWorkoutStatus() {
    final profileRef = _fitnessProfile;
    final colors = Theme.of(context).colorScheme;
    if (profileRef == null) {
      return _workoutStatusCard(
        isWorkoutDay: null,
        title: 'Fitness schedule unavailable',
        subtitle: 'Sign in to view your weekly training plan.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _workoutStatusCard(
            isWorkoutDay: null,
            title: 'Workout plan unavailable',
            subtitle: 'Fitness details could not be loaded.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: LinearProgressIndicator(),
            ),
          );
        }

        final profile = snapshot.data?.data() ?? <String, dynamic>{};
        final rawDays = profile['trainingDays'];
        final trainingDays = rawDays is List
            ? rawDays.map((day) => day.toString()).toSet()
            : <String>{'Mon', 'Wed', 'Fri'};
        final todayCode = _weekdays[_now.weekday - 1];
        final isWorkoutDay = trainingDays.contains(todayCode);
        final focus = profile['trainingFocus']?.toString();
        return _workoutStatusCard(
          isWorkoutDay: isWorkoutDay,
          title: isWorkoutDay ? 'Workout day' : 'Rest day',
          subtitle: isWorkoutDay
              ? (focus == null || focus.isEmpty
                  ? 'Today is on your weekly training plan.'
                  : 'Today is scheduled for $focus training.')
              : 'Today is not a scheduled training day. Make room for recovery.',
        );
      },
    );
  }

  Widget _workoutStatusCard({
    required bool? isWorkoutDay,
    required String title,
    required String subtitle,
  }) {
    if (isWorkoutDay == false) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final accent = isWorkoutDay == true
        ? const Color(0xFF2E8B57)
        : isWorkoutDay == false
            ? colors.secondary
            : colors.onSurfaceVariant;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isWorkoutDay == true ? Icons.fitness_center : Icons.self_improvement,
                color: accent,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            if (isWorkoutDay != null)
              Icon(isWorkoutDay ? Icons.bolt_rounded : Icons.spa_outlined, color: accent),
          ],
        ),
      ),
    );
  }

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

  Widget _sectionHeading(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _emptyPanel(BuildContext context, String message, {Widget? action}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: colors.onSurfaceVariant))),
          ?action,
        ],
      ),
    );
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }
}

class _HomeEvent {
  const _HomeEvent({required this.entry, required this.startsAt, this.endsAt});

  final Map<String, dynamic> entry;
  final DateTime startsAt;
  final DateTime? endsAt;
}
