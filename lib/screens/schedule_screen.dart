
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:test_ap_1/theme/app_colors.dart';

import '../services/schedule_service.dart';
import '../services/dashboard_calendar_cache.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  // OAuth Web application client ID from Google Cloud Console.
  static const String _googleServerClientId =
      '292778398931-auju0e8upqita3plmv19ot3e2fkc8tsf.apps.googleusercontent.com';
  static const List<String> _googleCalendarScopes = [
    // Read event details without allowing Trailblazer to modify events.
    'https://www.googleapis.com/auth/calendar.events.readonly',
    // Allows Trailblazer to discover the calendars on this Google account.
    'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
  ];

  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  // These colors are saved with each entry as an integer ARGB value.
  static const List<Color> _eventColors = [
    Color(0xFFFFE9E2), // orange
    Color(0xFFE2F0FA), // blue
    Color(0xFFE5F3E9), // green
    Color(0xFFF0E8FA), // purple
    Color(0xFFFFF3D8), // yellow
    Color(0xFFFCE4EC), // pink
  ];

  List<Map<String, dynamic>> _schedule = [];
  bool _isLoading = true;
  bool _showMonthView = false;
  String? _errorMessage;

  // Google Calendar data is kept separately from the locally saved schedule.
  GoogleSignInAccount? _googleAccount;
  List<Map<String, dynamic>> _googleEvents = [];
  static bool _googleSignInInitialized = false;
  bool _isGoogleCalendarLoading = false;
  String? _googleCalendarError;
  DateTime? _googleLoadedRangeStart;
  DateTime? _googleLoadedRangeEnd;

  late DateTime _weekStart;
  String _selectedDay = _weekdays[DateTime.now().weekday - 1];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _weekStart = _dateOnly(today.subtract(Duration(days: today.weekday - 1)));
    _loadSchedule();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _dateForDay(String day) {
    final index = _weekdays.indexOf(day);
    return _weekStart.add(Duration(days: index < 0 ? 0 : index));
  }

  Future<void> _initializeGoogleSignIn() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId,
    );
    _googleSignInInitialized = true;
  }

  DateTimeRange _visibleGoogleCalendarRange() {
    if (_showMonthView) {
      final start = DateTime(_weekStart.year, _weekStart.month, 1);
      final end = DateTime(_weekStart.year, _weekStart.month + 1, 1);
      return DateTimeRange(start: start, end: end);
    }
    return DateTimeRange(
      start: _weekStart,
      end: _weekStart.add(const Duration(days: 7)),
    );
  }

  Future<void> _connectGoogleCalendar() async {
    if (_isGoogleCalendarLoading) return;
    setState(() {
      _isGoogleCalendarLoading = true;
      _googleCalendarError = null;
    });
    try {
      await _initializeGoogleSignIn();
      final account = await GoogleSignIn.instance.authenticate();
      _googleAccount = account;
      final authorization = await account.authorizationClient
          .authorizeScopes(_googleCalendarScopes);
      await _loadGoogleCalendarEvents(authorization: authorization);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _googleCalendarError =
            'Could not connect to Google Calendar. Check your Google sign-in and Calendar API setup, then try again.';
        _isGoogleCalendarLoading = false;
      });
    }
  }

  Future<void> _refreshGoogleCalendar({bool force = true}) async {
    final account = _googleAccount;
    if (account == null || _isGoogleCalendarLoading) return;

    final range = _visibleGoogleCalendarRange();
    if (!force &&
        _googleLoadedRangeStart == range.start &&
        _googleLoadedRangeEnd == range.end) {
      return;
    }

    setState(() {
      _isGoogleCalendarLoading = true;
      _googleCalendarError = null;
    });
    try {
      await _initializeGoogleSignIn();
      var authorization = await account.authorizationClient
          .authorizationForScopes(_googleCalendarScopes);
      authorization ??= await account.authorizationClient
          .authorizeScopes(_googleCalendarScopes);
      await _loadGoogleCalendarEvents(authorization: authorization);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _googleCalendarError = 'Google Calendar could not be refreshed. Please reconnect and try again.';
        _isGoogleCalendarLoading = false;
      });
    }
  }

  Future<void> _loadGoogleCalendarEvents({
    required GoogleSignInClientAuthorization authorization,
  }) async {
    final range = _visibleGoogleCalendarRange();
    final client = authorization.authClient(scopes: _googleCalendarScopes);
    try {
      final api = calendar.CalendarApi(client);
      final imported = <Map<String, dynamic>>[];
      final seenEventKeys = <String>{};
      String? calendarPageToken;
      var calendarErrors = 0;

      // Discover every calendar on the account, including calendars hidden
      // from the Google Calendar sidebar and calendars shared with the user.
      do {
        final calendarPage = await api.calendarList.list(
          showHidden: true,
          maxResults: 250,
          pageToken: calendarPageToken,
        );

        for (final calendarEntry
            in calendarPage.items ?? <calendar.CalendarListEntry>[]) {
          final calendarId = calendarEntry.id;
          if (calendarId == null || calendarId.isEmpty) continue;
          final calendarName =
              (calendarEntry.summaryOverride?.trim().isNotEmpty ?? false)
                  ? calendarEntry.summaryOverride!.trim()
                  : (calendarEntry.summary?.trim().isNotEmpty ?? false)
                      ? calendarEntry.summary!.trim()
                      : 'Google Calendar';

          try {
            String? eventPageToken;
            do {
              final eventPage = await api.events.list(
                calendarId,
                timeMin: range.start.toUtc(),
                timeMax: range.end.toUtc(),
                singleEvents: true,
                orderBy: 'startTime',
                maxResults: 2500,
                pageToken: eventPageToken,
              );

              for (final event in eventPage.items ?? <calendar.Event>[]) {
                final startValue = event.start?.dateTime ?? event.start?.date;
                if (startValue == null) continue;

                // A copied event may be visible through more than one
                // subscribed calendar. Keep only one display entry for the
                // same Google event occurrence.
                final eventIdentity = event.iCalUID ?? event.id ?? calendarId;
                final eventKey =
                    '$eventIdentity|${startValue.toIso8601String()}|${event.summary ?? ''}';
                if (!seenEventKeys.add(eventKey)) continue;

                final endValue = event.end?.dateTime ?? event.end?.date;
                final start = startValue.toLocal();
                final end = endValue?.toLocal();
                final duration =
                    end == null ? 0 : end.difference(start).inMinutes;
                imported.add({
                  'externalGoogle': true,
                  'googleEventId': event.id ?? '',
                  'googleCalendarId': calendarId,
                  'googleCalendarName': calendarName,
                  'name': (event.summary?.trim().isNotEmpty ?? false)
                      ? event.summary!.trim()
                      : '(No title)',
                  'location': event.location ?? '',
                  'date': _dateOnly(start).toIso8601String(),
                  'startTime': event.start?.dateTime == null
                      ? null
                      : _timeToStorage(TimeOfDay.fromDateTime(start)),
                  'endTime': event.end?.dateTime == null || end == null
                      ? null
                      : _timeToStorage(TimeOfDay.fromDateTime(end)),
                  'duration': duration,
                  'allDay': event.start?.date != null,
                  'repeatWeekly': false,
                  'repeatYearly': false,
                });
              }
              eventPageToken = eventPage.nextPageToken;
            } while (eventPageToken != null);
          } catch (_) {
            // A calendar with restricted access should not prevent the other
            // calendars from loading.
            calendarErrors++;
          }
        }

        calendarPageToken = calendarPage.nextPageToken;
      } while (calendarPageToken != null);

      if (!mounted) return;
      setState(() {
        _googleEvents = imported;
        _googleLoadedRangeStart = range.start;
        _googleLoadedRangeEnd = range.end;
        _googleCalendarError = calendarErrors > 0
            ? 'Some Google calendars could not be read. Other calendars were still loaded.'
            : null;
        _isGoogleCalendarLoading = false;
      });
      // Keep the Home dashboard in sync with the latest read-only import.
      DashboardCalendarCache.instance.update(imported);
    } finally {
      client.close();
    }
  }

  Future<void> _copyGoogleEventToSchedule(
    Map<String, dynamic> googleEvent,
  ) async {
    final eventId = googleEvent['googleEventId']?.toString() ?? '';
    final calendarId = googleEvent['googleCalendarId']?.toString() ?? '';
    final date = googleEvent['date']?.toString() ?? '';
    final sourceKey = '$calendarId|$eventId|$date';

    final alreadyCopied = _schedule.any(
      (entry) => entry['googleSourceKey'] == sourceKey,
    );
    if (alreadyCopied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This Google Calendar event is already in Trailblazer.')),
      );
      return;
    }

    final seed = <String, dynamic>{
      'name': googleEvent['name'] ?? '(No title)',
      'location': googleEvent['location'] ?? '',
      'date': date,
      'startTime': googleEvent['startTime'],
      'endTime': googleEvent['endTime'],
      'duration': googleEvent['duration'] ?? 0,
      'allDay': googleEvent['allDay'] == true,
      'repeatFrequency': 'none',
      'repeatWeekly': false,
      'repeatYearly': false,
      'days': <String>[],
      'googleSourceKey': sourceKey,
      'colorValue': _eventColors[1].toARGB32(),
    };

    await _openScheduleEditor(entry: seed);
    if (!mounted) return;
    if (_schedule.any((entry) => entry['googleSourceKey'] == sourceKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google event copied to your Trailblazer schedule.')),
      );
    }
  }

  bool _googleEventOccursOn(DateTime date) {
    return _googleEvents.any((event) {
      final parsed = DateTime.tryParse(event['date']?.toString() ?? '');
      return parsed != null && _dateOnly(parsed) == _dateOnly(date);
    });
  }

  Future<void> _loadSchedule() async {
    try {
      final entries = await ScheduleService.loadEntries();
      if (!mounted) return;
      setState(() {
        _schedule = entries
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load your schedule.';
      });
    }
  }

  Future<void> _persistSchedule(List<Map<String, dynamic>> updated) async {
    try {
      await ScheduleService.saveEntries(updated);
      if (!mounted) return;
      setState(() {
        _schedule = updated;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save your schedule.')),
      );
    }
  }

  Future<void> _saveScheduleEntry(
    Map<String, dynamic> entry, {
    int? index,
  }) async {
    final updated = List<Map<String, dynamic>>.from(_schedule);
    if (index == null) {
      updated.add(entry);
    } else if (index >= 0 && index < updated.length) {
      updated[index] = entry;
    } else {
      return;
    }
    await _persistSchedule(updated);
  }

  Future<void> _deleteScheduleEntry(int index) async {
    if (index < 0 || index >= _schedule.length) return;

    final entry = _schedule[index];
    final name = entry['name']?.toString() ?? 'this entry';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete schedule entry?'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final updated = List<Map<String, dynamic>>.from(_schedule)
      ..removeAt(index);
    await _persistSchedule(updated);
  }

  List<String> _daysForEntry(Map<String, dynamic> entry) {
    final rawDays = entry['days'];
    if (rawDays is List && rawDays.isNotEmpty) {
      return rawDays.map((day) => day.toString())
          .where(_weekdays.contains).toSet().toList();
    }
    final legacyDay = entry['day']?.toString();
    if (legacyDay != null && _weekdays.contains(legacyDay)) {
      return [legacyDay];
    }
    return [];
  }

  bool _entryOccursOnDate(Map<String, dynamic> entry, DateTime date) {
    if (entry['entryType'] == 'todo') return false;

    // New entries use repeatFrequency. Older saved entries keep working via
    // their original repeatWeekly/repeatYearly fields.
    final frequency = entry['repeatFrequency']?.toString() ??
        (entry['repeatYearly'] == true
            ? 'yearly'
            : entry['repeatWeekly'] == false
                ? 'none'
                : 'weekly');
    final selected = _dateOnly(date);

    // Legacy weekly entries intentionally have no anchor date.
    if (frequency == 'weekly') {
      return _daysForEntry(entry).contains(_weekdays[selected.weekday - 1]);
    }

    final startDate = DateTime.tryParse(entry['date']?.toString() ?? '');
    if (startDate == null) return false;
    final anchor = _dateOnly(startDate);
    if (selected.isBefore(anchor)) return false;
    final repeatUntil = DateTime.tryParse(entry['repeatUntil']?.toString() ?? '');
    if (repeatUntil != null && selected.isAfter(_dateOnly(repeatUntil))) {
      return false;
    }

    switch (frequency) {
      case 'daily':
        return true;
      case 'monthly':
        return selected.day == anchor.day;
      case 'yearly':
        return selected.month == anchor.month && selected.day == anchor.day;
      case 'none':
      default:
        return selected == anchor;
    }
  }

  bool _isVisibleOnSelectedDay(Map<String, dynamic> entry) =>
      _entryOccursOnDate(entry, _dateForDay(_selectedDay));

  List<MapEntry<int, Map<String, dynamic>>> _todosForSelectedDay() {
    final selectedDate = _dateForDay(_selectedDay);
    final todos = _schedule.asMap().entries.where((entry) {
      final item = entry.value;
      if (item['entryType'] != 'todo') return false;
      final parsed = DateTime.tryParse(item['date']?.toString() ?? '');
      return parsed != null && _dateOnly(parsed) == selectedDate;
    }).toList();
    todos.sort((a, b) {
      final importanceA = (a.value['importance'] as num?)?.toInt() ?? 1;
      final importanceB = (b.value['importance'] as num?)?.toInt() ?? 1;
      if (importanceA != importanceB) return importanceB.compareTo(importanceA);
      return a.key.compareTo(b.key);
    });
    return todos;
  }

  Future<void> _addTodo() async {
    // Let TextFormField manage its own controller lifecycle. A manually
    // disposed controller can still be accessed while Flutter is closing
    // the keyboard/focus connection for this dialog.
    String taskTitle = '';
    int importance = 3;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: taskTitle,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) => taskTitle = value,
                decoration: const InputDecoration(
                  labelText: 'Task',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Importance'),
                  const Spacer(),
                  Text(
                    '$importance / 5',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF263746)),
                  ),
                ],
              ),
              Slider(
                value: importance.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$importance',
                onChanged: (value) {
                  setDialogState(() {
                    importance = value.round();
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = taskTitle.trim();
                if (title.isEmpty) return;

                Navigator.pop(dialogContext, {
                  'entryType': 'todo',
                  'name': title,
                  'date': _dateOnly(
                    _dateForDay(_selectedDay),
                  ).toIso8601String(),
                  'completed': false,
                  'importance': importance,
                });
              },
              child: const Text('Add task'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      await _saveScheduleEntry(result);
    }
  }

  Future<void> _toggleTodo(int index, bool completed) async {
    final updated = List<Map<String, dynamic>>.from(_schedule);
    updated[index] = {...updated[index], 'completed': completed};
    await _persistSchedule(updated);
  }

  Widget _buildTodoSection() {
    final todos = _todosForSelectedDay();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('To-do list',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const Spacer(),
              Text('${todos.where((e) => e.value['completed'] == true).length}/${todos.length} done',
                  style: Theme.of(context).textTheme.bodySmall),
              IconButton(
                tooltip: 'Add task',
                onPressed: _addTodo,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (todos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No tasks for this day. Add one when you need it.'),
            )
          else
            ...todos.map((todo) {
              final item = todo.value;
              final completed = item['completed'] == true;
              final importance = (item['importance'] as num?)?.toInt() ?? 1;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: CheckboxListTile(
                  value: completed,
                  onChanged: (value) => _toggleTodo(todo.key, value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    item['name']?.toString() ?? 'Task',
                    style: TextStyle(
                      decoration: completed ? TextDecoration.lineThrough : null,
                      color: completed ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                    ),
                  ),
                  subtitle: Text('Importance: $importance / 5'),
                  secondary: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') _deleteScheduleEntry(todo.key);
                      if (value.startsWith('rank')) {
                        final rank = int.parse(value.substring(4));
                        final updated = List<Map<String, dynamic>>.from(_schedule);
                        updated[todo.key] = {...updated[todo.key], 'importance': rank};
                        _persistSchedule(updated);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      for (var rank = 1; rank <= 5; rank++)
                        PopupMenuItem(value: 'rank$rank', child: Text('Set importance $rank')),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  int _minutesFromTime(String? value) {
    if (value == null || !value.contains(':')) return -1;
    final parts = value.split(':');
    if (parts.length != 2) return -1;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return -1;
    return hour * 60 + minute;
  }

  String _formatTime(String? value) {
    final minutes = _minutesFromTime(value);
    if (minutes < 0) return 'Time not set';
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return time.format(context);
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return 'Duration not set';
    final hours = minutes ~/ 60;
    final leftover = minutes % 60;
    if (hours > 0 && leftover > 0) {
      return '$hours hr $leftover min';
    }
    if (hours > 0) return '$hours hr';
    return '$leftover min';
  }

  List<MapEntry<int, Map<String, dynamic>>> _entriesForSelectedDay() {
    final selectedDate = _dateForDay(_selectedDay);
    final entries = _schedule.asMap().entries
        .where((entry) => _isVisibleOnSelectedDay(entry.value))
        .toList();

    // Negative indexes identify imported Google events. They are display-only
    // and are never passed to local edit/delete persistence methods.
    for (var i = 0; i < _googleEvents.length; i++) {
      final event = _googleEvents[i];
      final parsed = DateTime.tryParse(event['date']?.toString() ?? '');
      if (parsed != null && _dateOnly(parsed) == selectedDate) {
        entries.add(MapEntry(-(i + 1), event));
      }
    }

    entries.sort((a, b) {
      final aTime = _minutesFromTime(a.value['startTime']?.toString());
      final bTime = _minutesFromTime(b.value['startTime']?.toString());
      final safeA = aTime < 0 ? 24 * 60 + a.key.abs() : aTime;
      final safeB = bTime < 0 ? 24 * 60 + b.key.abs() : bTime;
      return safeA.compareTo(safeB);
    });
    return entries;
  }

  Future<void> _pickTime({
    required BuildContext dialogContext,
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: dialogContext,
      initialTime: initial,
    );
    if (picked != null) onPicked(picked);
  }

  String _timeToStorage(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _openScheduleEditor({
    Map<String, dynamic>? entry,
    int? index,
  }) async {
    // TextFormField owns its internal controllers. This avoids disposing
    // controllers while Flutter is still processing focus/keyboard changes
    // as the dialog closes.
    String name = entry?['name']?.toString() ?? '';
    String location = entry?['location']?.toString() ?? '';

    final oldStart = _minutesFromTime(entry?['startTime']?.toString());
    final oldEnd = _minutesFromTime(entry?['endTime']?.toString());
    TimeOfDay startTime = oldStart < 0
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: oldStart ~/ 60, minute: oldStart % 60);
    TimeOfDay endTime = oldEnd < 0
        ? const TimeOfDay(hour: 10, minute: 0)
        : TimeOfDay(hour: oldEnd ~/ 60, minute: oldEnd % 60);

    String repeatFrequency = entry == null
        ? 'weekly'
        : entry['repeatFrequency']?.toString() ??
            (entry['repeatYearly'] == true
                ? 'yearly'
                : entry['repeatWeekly'] == false
                    ? 'none'
                    : 'weekly');
    bool allDay = entry?['allDay'] == true;
    List<String> selectedDays = entry == null
        ? [_selectedDay]
        : _daysForEntry(entry);
    if (selectedDays.isEmpty) selectedDays = [_selectedDay];

    DateTime selectedDate = DateTime.tryParse(
          entry?['date']?.toString() ?? '',
        ) ??
        _dateForDay(_selectedDay);
    DateTime? repeatUntil = DateTime.tryParse(
      entry?['repeatUntil']?.toString() ?? '',
    );

    int selectedColor = (entry?['colorValue'] as num?)?.toInt() ??
        _eventColors.first.toARGB32();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final startMinutes = startTime.hour * 60 + startTime.minute;
            final endMinutes = endTime.hour * 60 + endTime.minute;
            final duration = endMinutes - startMinutes;

            return AlertDialog(
              title: Text(index == null
                  ? 'Add class or activity'
                  : 'Edit schedule entry'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        initialValue: name,
                        onChanged: (value) => name = value,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Class or activity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: location,
                        onChanged: (value) => location = value,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Location (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('All-day event'),
                        value: allDay,
                        onChanged: (value) => setDialogState(() => allDay = value),
                      ),
                      if (!allDay) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Start and end time',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.access_time),
                                label: Text(startTime.format(context)),
                                onPressed: () => _pickTime(
                                  dialogContext: dialogContext,
                                  initial: startTime,
                                  onPicked: (time) => setDialogState(
                                    () => startTime = time,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.flag_outlined),
                                label: Text(endTime.format(context)),
                                onPressed: () => _pickTime(
                                  dialogContext: dialogContext,
                                  initial: endTime,
                                  onPicked: (time) => setDialogState(
                                    () => endTime = time,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!allDay && duration > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Duration: ${_formatMinutes(duration)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: repeatFrequency,
                        decoration: const InputDecoration(
                          labelText: 'Repeat',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
                          DropdownMenuItem(value: 'daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                          DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => repeatFrequency = value);
                        },
                      ),
                      if (repeatFrequency != 'none') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                repeatUntil == null
                                    ? 'No end date'
                                    : 'Ends ${repeatUntil!.month}/${repeatUntil!.day}/${repeatUntil!.year}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: repeatUntil ?? selectedDate,
                                  firstDate: selectedDate,
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() => repeatUntil = picked);
                                }
                              },
                              child: Text(repeatUntil == null ? 'Set end date' : 'Change'),
                            ),
                            if (repeatUntil != null)
                              IconButton(
                                tooltip: 'Remove end date',
                                onPressed: () => setDialogState(() => repeatUntil = null),
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (repeatFrequency == 'weekly') ...[
                        const Text(
                          'Repeat on',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _weekdays.map((day) {
                            final selected = selectedDays.contains(day);
                            return FilterChip(
                              label: Text(day),
                              selected: selected,
                              selectedColor: AppColors.actionBlue
                                  .withValues(alpha: 0.2),
                              onSelected: (value) {
                                setDialogState(() {
                                  if (value) {
                                    selectedDays.add(day);
                                  } else if (selectedDays.length > 1) {
                                    selectedDays.remove(day);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ] else ...[
                        const Text(
                          'Start date',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Card color',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: _eventColors.map((color) {
                          final selected = selectedColor == color.toARGB32();
                          return GestureDetector(
                            onTap: () => setDialogState(
                              () => selectedColor = color.toARGB32(),
                            ),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.navigationNavy
                                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
                                  width: selected ? 3 : 1,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navigationNavy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final eventName = name.trim();
                    final eventLocation = location.trim();

                    if (eventName.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a name for this event.'),
                        ),
                      );
                      return;
                    }
                    if (!allDay && duration <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('End time must be after start time.'),
                        ),
                      );
                      return;
                    }
                    if (repeatFrequency == 'weekly' && selectedDays.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Select at least one weekday.'),
                        ),
                      );
                      return;
                    }

                    selectedDays.sort(
                      (a, b) => _weekdays.indexOf(a)
                          .compareTo(_weekdays.indexOf(b)),
                    );

                    Navigator.pop(dialogContext, {
                      'name': eventName,
                      'location': eventLocation,
                      // Keep duration for compatibility with older entries.
                      'duration': duration,
                      // Keep day for compatibility with the original format.
                      'day': repeatFrequency == 'weekly'
                          ? selectedDays.first
                          : _weekdays[selectedDate.weekday - 1],
                      'days': repeatFrequency == 'weekly' ? selectedDays : <String>[],
                      'repeatFrequency': repeatFrequency,
                      'repeatWeekly': repeatFrequency == 'weekly',
                      'repeatYearly': repeatFrequency == 'yearly',
                      'date': _dateOnly(selectedDate).toIso8601String(),
                      'repeatUntil': repeatFrequency == 'none' || repeatUntil == null
                          ? null
                          : _dateOnly(repeatUntil!).toIso8601String(),
                      'allDay': allDay,
                      'startTime': allDay ? null : _timeToStorage(startTime),
                      'endTime': allDay ? null : _timeToStorage(endTime),
                      'googleSourceKey': entry?['googleSourceKey'],
                      'colorValue': selectedColor,
                    });
                  },
                  child: const Text('Save entry'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      await _saveScheduleEntry(result, index: index);
    }
  }

  void _changeWeek(int amount) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: amount * 7));
    });
    _refreshGoogleCalendar(force: false);
  }

  String _weekLabel() {
    final end = _weekStart.add(const Duration(days: 6));
    return '${_monthName(_weekStart.month)} ${_weekStart.day} – '
        '${_monthName(end.month)} ${end.day}';
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildMonthGrid() {
    final first = DateTime(_weekStart.year, _weekStart.month, 1);
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(_weekStart.year, _weekStart.month + 1, 0).day;
    final count = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final selected = _dateForDay(_selectedDay);
    return Column(
      children: [
        Row(
          children: _weekdays.map((day) => Expanded(
            child: Center(child: Text(day, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          )).toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - offset + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox.shrink();
            final date = DateTime(_weekStart.year, _weekStart.month, dayNumber);
            final isSelected = _dateOnly(selected) == date;
            final hasEntries = _googleEventOccursOn(date) ||
                _schedule.any((entry) => _entryOccursOnDate(entry, date));
            return InkWell(
              onTap: () {
                setState(() {
                  _weekStart = _dateOnly(date.subtract(Duration(days: date.weekday - 1)));
                  _selectedDay = _weekdays[date.weekday - 1];
                });
                if (!_showMonthView) _refreshGoogleCalendar(force: false);
              },
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.navigationNavy : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$dayNumber', style: TextStyle(
                      color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    )),
                    if (hasEntries) Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : AppColors.actionBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeekSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () {
                if (_showMonthView) {
                  setState(() => _weekStart = DateTime(_weekStart.year, _weekStart.month - 1, 1));
                  _refreshGoogleCalendar(force: false);
                } else {
                  _changeWeek(-1);
                }
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() => _showMonthView = !_showMonthView);
                  _refreshGoogleCalendar(force: false);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Text(
                        _showMonthView
                            ? '${_monthName(_weekStart.month)} ${_weekStart.year}'
                            : _weekLabel(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('Tap to view month',
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: () {
                if (_showMonthView) {
                  setState(() => _weekStart = DateTime(_weekStart.year, _weekStart.month + 1, 1));
                  _refreshGoogleCalendar(force: false);
                } else {
                  _changeWeek(1);
                }
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (_showMonthView) ...[
          const SizedBox(height: 8),
          _buildMonthGrid(),
        ] else
        Row(
          children: List.generate(_weekdays.length, (index) {
            final day = _weekdays[index];
            final date = _weekStart.add(Duration(days: index));
            final selected = _selectedDay == day;
            final isToday = _dateOnly(DateTime.now()) == date;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _selectedDay = day),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.navigationNavy
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: isToday && !selected
                          ? Border.all(color: AppColors.actionBlue)
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          day,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: selected
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildEntryCard(
    MapEntry<int, Map<String, dynamic>> scheduleEntry,
  ) {
    final index = scheduleEntry.key;
    final item = scheduleEntry.value;
    final title = item['name']?.toString() ?? 'Entry';
    final location = item['location']?.toString() ?? '';
    final start = item['startTime']?.toString();
    final end = item['endTime']?.toString();
    final duration = (item['duration'] as num?)?.toInt() ?? 0;
    final colorValue = (item['colorValue'] as num?)?.toInt();
    final cardColor = colorValue == null
        ? _eventColors.first
        : Color(colorValue);
    final frequency = item['repeatFrequency']?.toString() ??
        (item['repeatYearly'] == true
            ? 'yearly'
            : item['repeatWeekly'] == false
                ? 'none'
                : 'weekly');
    final isGoogleEvent = item['externalGoogle'] == true;
    final googleCalendarName =
        item['googleCalendarName']?.toString() ?? 'Google Calendar';
    final repeatLabel = frequency == 'none'
        ? ''
        : '\nRepeats ${frequency == 'weekly' ? 'weekly' : frequency}';

    final timeText = item['allDay'] == true
        ? 'All day'
        : _minutesFromTime(start) >= 0 && _minutesFromTime(end) >= 0
            ? '${_formatTime(start)} – ${_formatTime(end)}'
            : _formatMinutes(duration);

    return Card(
      color: cardColor,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        leading: CircleAvatar(
          backgroundColor: isGoogleEvent ? const Color(0xFF4285F4) : AppColors.actionBlue,
          foregroundColor: Colors.white,
          child: Icon(isGoogleEvent ? Icons.cloud_outlined : Icons.calendar_today_outlined),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF263746)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$timeText${location.isEmpty ? '' : '\n$location'}'
            '${isGoogleEvent ? '\n$googleCalendarName' : repeatLabel}',
          ),
        ),
        isThreeLine: true,
        trailing: isGoogleEvent
            ? PopupMenuButton<String>(
                tooltip: 'Google event options',
                onSelected: (value) {
                  if (value == 'copy') _copyGoogleEventToSchedule(item);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      leading: Icon(Icons.copy_outlined),
                      title: Text('Copy to Trailblazer'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Tooltip(
                    message: 'Imported read-only · Tap to copy',
                    child: Icon(Icons.copy_outlined, color: Color(0xFF4285F4)),
                  ),
                ),
              )
            : PopupMenuButton<String>(
                tooltip: 'Entry options',
                onSelected: (value) {
                  if (value == 'edit') {
                    _openScheduleEditor(entry: item, index: index);
                  } else if (value == 'delete') {
                    _deleteScheduleEntry(index);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final dayEntries = _entriesForSelectedDay();
    _todosForSelectedDay();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorMessage!),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadSchedule, child: const Text('Try again')),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 100),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('My Schedule', style: Theme.of(context).textTheme.headlineSmall),
                                  const SizedBox(height: 6),
                                  const Text('Manage your classes, activities, and tasks.'),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _isGoogleCalendarLoading
                                              ? null
                                              : (_googleAccount == null
                                                  ? _connectGoogleCalendar
                                                  : () => _refreshGoogleCalendar(force: true)),
                                          icon: _isGoogleCalendarLoading
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Icon(Icons.calendar_month_outlined),
                                          label: Text(_googleAccount == null
                                              ? 'Connect Google Calendar'
                                              : 'Refresh Google Calendar'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_googleCalendarError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        _googleCalendarError!,
                                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  _buildWeekSelector(),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Text(
                                        _showMonthView
                                            ? '${_monthName(_dateForDay(_selectedDay).month)} ${_dateForDay(_selectedDay).day} activities'
                                            : '$_selectedDay\'s activities',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const Spacer(),
                                      Text('${dayEntries.length} ${dayEntries.length == 1 ? 'entry' : 'entries'}',
                                          style: Theme.of(context).textTheme.bodySmall),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (dayEntries.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
                                child: Text('No classes or events scheduled for this day.'),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Column(
                                  children: dayEntries.map(_buildEntryCard).toList(),
                                ),
                              ),
                            const Divider(height: 24),
                            _buildTodoSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.navigationNavy,
        foregroundColor: Colors.white,
        onPressed: () => _openScheduleEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add event'),
      ),
    );
  }
}


