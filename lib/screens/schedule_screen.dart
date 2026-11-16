import 'package:flutter/material.dart';
import 'package:test_ap_1/theme/app_colors.dart';

import '../services/schedule_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
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
  String? _errorMessage;

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

  bool _isVisibleOnSelectedDay(Map<String, dynamic> entry) {
    final repeats = entry['repeatWeekly'] != false;
    if (repeats) {
      return _daysForEntry(entry).contains(_selectedDay);
    }

    final rawDate = entry['date']?.toString();
    if (rawDate == null) return false;
    final parsedDate = DateTime.tryParse(rawDate);
    if (parsedDate == null) return false;
    final eventDate = _dateOnly(parsedDate);
    final selectedDate = _dateForDay(_selectedDay);
    return eventDate == selectedDate;
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
    final entries = _schedule.asMap().entries
        .where((entry) => _isVisibleOnSelectedDay(entry.value))
        .toList();

    // Entries with a start time are ordered chronologically. Legacy entries
    // without a start time appear after timed entries.
    entries.sort((a, b) {
      final aTime = _minutesFromTime(a.value['startTime']?.toString());
      final bTime = _minutesFromTime(b.value['startTime']?.toString());
      final safeA = aTime < 0 ? 24 * 60 + a.key : aTime;
      final safeB = bTime < 0 ? 24 * 60 + b.key : bTime;
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
    final nameController = TextEditingController(
      text: entry?['name']?.toString() ?? '',
    );
    final locationController = TextEditingController(
      text: entry?['location']?.toString() ?? '',
    );

    final oldStart = _minutesFromTime(entry?['startTime']?.toString());
    final oldEnd = _minutesFromTime(entry?['endTime']?.toString());
    TimeOfDay startTime = oldStart < 0
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: oldStart ~/ 60, minute: oldStart % 60);
    TimeOfDay endTime = oldEnd < 0
        ? const TimeOfDay(hour: 10, minute: 0)
        : TimeOfDay(hour: oldEnd ~/ 60, minute: oldEnd % 60);

    bool repeatWeekly = entry?['repeatWeekly'] != false;
    List<String> selectedDays = entry == null
        ? [_selectedDay]
        : _daysForEntry(entry);
    if (selectedDays.isEmpty) selectedDays = [_selectedDay];

    DateTime selectedDate = DateTime.tryParse(
          entry?['date']?.toString() ?? '',
        ) ??
        _dateForDay(_selectedDay);

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
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Class or activity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: locationController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                      if (duration > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Duration: ${_formatMinutes(duration)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Repeat weekly'),
                        subtitle: const Text(
                          'Keep this entry on the selected weekday(s).',
                        ),
                        value: repeatWeekly,
                        onChanged: (value) => setDialogState(
                          () => repeatWeekly = value,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (repeatWeekly) ...[
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
                          'Date',
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
                                      : Colors.black26,
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
                    final name = nameController.text.trim();
                    final location = locationController.text.trim();

                    if (name.isEmpty || location.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a name and location.'),
                        ),
                      );
                      return;
                    }
                    if (duration <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('End time must be after start time.'),
                        ),
                      );
                      return;
                    }
                    if (repeatWeekly && selectedDays.isEmpty) {
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
                      'name': name,
                      'location': location,
                      // Keep duration for compatibility with older entries.
                      'duration': duration,
                      // Keep day for compatibility with the original format.
                      'day': repeatWeekly ? selectedDays.first : _weekdays[
                        selectedDate.weekday - 1
                      ],
                      'days': repeatWeekly ? selectedDays : <String>[],
                      'repeatWeekly': repeatWeekly,
                      'date': repeatWeekly
                          ? null
                          : _dateOnly(selectedDate).toIso8601String(),
                      'startTime': _timeToStorage(startTime),
                      'endTime': _timeToStorage(endTime),
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

    nameController.dispose();
    locationController.dispose();

    if (result != null && mounted) {
      await _saveScheduleEntry(result, index: index);
    }
  }

  void _changeWeek(int amount) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: amount * 7));
    });
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

  Widget _buildWeekSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous week',
              onPressed: () => _changeWeek(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _weekLabel(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Next week',
              onPressed: () => _changeWeek(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
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
                                : const Color(0xFF5D6670),
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
                                : AppColors.navigationNavy,
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
    final isRepeating = item['repeatWeekly'] != false;

    final timeText = _minutesFromTime(start) >= 0 &&
            _minutesFromTime(end) >= 0
        ? '${_formatTime(start)} – ${_formatTime(end)}'
        : _formatMinutes(duration);

    return Card(
      color: cardColor,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.actionBlue,
          foregroundColor: Colors.white,
          child: const Icon(Icons.calendar_today_outlined),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$timeText\n$location'
            '${isRepeating ? '\nRepeats weekly' : ''}',
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
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

  Widget _buildEmptyState({required bool noEntriesAtAll}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 58,
              color: AppColors.navigationNavy.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 14),
            Text(
              noEntriesAtAll
                  ? 'No classes scheduled yet'
                  : 'Nothing planned for $_selectedDay',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              noEntriesAtAll
                  ? 'Add your classes and activities to organize your week.'
                  : 'Enjoy the free time, or add an activity for this day.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayEntries = _entriesForSelectedDay();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
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
                        ElevatedButton(
                          onPressed: _loadSchedule,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _schedule.isEmpty
                            ? _buildEmptyState(noEntriesAtAll: true)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20, 20, 20, 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'My Schedule',
                                          style: Theme.of(context)
                                              .textTheme.headlineSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Manage your classes and weekly activities.',
                                        ),
                                        const SizedBox(height: 12),
                                        _buildWeekSelector(),
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Text(
                                              '$_selectedDay\'s activities',
                                              style: Theme.of(context)
                                                  .textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${dayEntries.length} '
                                              '${dayEntries.length == 1 ? 'entry' : 'entries'}',
                                              style: Theme.of(context)
                                                  .textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: dayEntries.isEmpty
                                        ? _buildEmptyState(
                                            noEntriesAtAll: false,
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(
                                              20, 4, 20, 100,
                                            ),
                                            itemCount: dayEntries.length,
                                            itemBuilder: (context, index) =>
                                                _buildEntryCard(
                                              dayEntries[index],
                                            ),
                                          ),
                                  ),
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
        label: const Text('Add class'),
      ),
    );
  }
}
