import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:test_ap_1/theme/app_colors.dart';

import '../services/app_settings.dart';
import '../services/points_service.dart';

/// Displays the user's daily hydration and sleep information, along with a
/// seven-day history of both metrics.
///
/// Water values are stored in milliliters in Firestore regardless of the
/// selected measurement system. This keeps historical records consistent;
/// conversion happens only when values are displayed or entered.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  // Daily targets. Water is persisted in milliliters so existing Firestore
  // history remains compatible when the user changes measurement systems.
  static const int waterGoal = 2000;
  static const double sleepGoal = 8.0;

  // Conversion factor for US fluid ounces. The stored value remains milliliters.
  static const double _millilitersPerUsFluidOunce = 29.5735;

  // Read the current unit preference from the shared app settings service.
  bool get _isMetric => AppSettings.instance.isMetric;
  String get _waterUnit => _isMetric ? 'ml' : 'fl oz';

  // Convert a stored milliliter value for display without changing the source.
  double _displayWater(int milliliters) =>
      _isMetric ? milliliters.toDouble() : milliliters / _millilitersPerUsFluidOunce;

  // Format a water amount using the user's preferred unit and a whole number.
  String _formatWater(int milliliters) {
    final value = _displayWater(milliliters);
    return _isMetric ? '${value.round()} ml' : '${value.round()} fl oz';
  }

  // The add-water button uses approximately one cup in either unit system.
  int get _waterIncrementMl => _isMetric ? 250 : 237;
  String get _waterIncrementLabel => _isMetric ? '+250 ml' : '+8 fl oz';

  // Current-day values shown in the daily tracker.
  int waterIntake = 0;
  double sleepHours = 0;

  // Loading and saving flags prevent conflicting interactions and show progress.
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Dates are normalized to midnight so date comparisons and Firestore keys
  // are independent of the current time of day.
  late DateTime _today;
  late DateTime _weekStart;

  // Cached records for the selected week, keyed by yyyy-MM-dd.
  Map<String, Map<String, dynamic>> _weekLogs = {};

  // The active Firebase user owns all health records stored by this screen.
  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();

    // Refresh displayed units when the user changes the app's measurement
    // preference, then establish the current date/week and load saved records.
    AppSettings.instance.addListener(_onAppSettingsChanged);
    _today = _dateOnly(DateTime.now());
    _weekStart = _mondayOf(_today);
    _loadHealthData();
  }

  // Rebuild the screen when shared app settings change.
  void _onAppSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Remove the settings listener to avoid callbacks after this screen closes.
    AppSettings.instance.removeListener(_onAppSettingsChanged);
    super.dispose();
  }

  // Remove the time component from a DateTime for date-only calculations.
  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  // Return the Monday that begins the week containing [date].
  DateTime _mondayOf(DateTime date) =>
      _dateOnly(date.subtract(Duration(days: date.weekday - 1)));

  // Use a stable date key for Firestore document IDs and in-memory lookups.
  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// Builds the signed-in user's health-log document for a specific date.
  ///
  /// A missing authenticated user is treated as an error because health data
  /// must always be associated with an account.
  DocumentReference<Map<String, dynamic>> _dayDocument(DateTime date) {
    final user = _user;
    if (user == null) {
      throw StateError('You must be signed in to save health information.');
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('health_logs')
        .doc(_dateKey(date));
  }

  // Fetch one day's record. A missing document is represented as an empty map.
  Future<Map<String, dynamic>> _readDay(DateTime date) async {
    final snapshot = await _dayDocument(date).get();
    return snapshot.data() ?? <String, dynamic>{};
  }

  /// Loads today's values and the records for the current week.
  ///
  /// Both reads run together. The result is applied only while this widget is
  /// still mounted, preventing asynchronous work from updating a disposed UI.
  Future<void> _loadHealthData() async {
    if (_user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please sign in to save and view your health history.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _readDay(_today),
        _loadWeekRecords(_weekStart),
      ]);
      if (!mounted) return;

      final todayData = results[0];
      final weekData = results[1] as Map<String, Map<String, dynamic>>;
      setState(() {
        waterIntake = (todayData['waterIntake'] as num?)?.toInt() ?? 0;
        sleepHours = (todayData['sleepHours'] as num?)?.toDouble() ?? 0;
        _weekLogs = weekData;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load your health history. Check your connection and try again.';
      });
    }
  }

  /// Reads all seven daily documents for the week beginning on [weekStart].
  ///
  /// Each record is stored in a map under its date key so the weekly chart can
  /// retrieve values in calendar order, including days with no saved entry.
  Future<Map<String, Map<String, dynamic>>> _loadWeekRecords(
    DateTime weekStart,
  ) async {
    final dates = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final snapshots = await Future.wait(
      dates.map((date) => _dayDocument(date).get()),
    );

    final records = <String, Map<String, dynamic>>{};
    for (var index = 0; index < dates.length; index++) {
      records[_dateKey(dates[index])] =
          snapshots[index].data() ?? <String, dynamic>{};
    }
    return records;
  }

  /// Moves the weekly history backward or forward by [amount] weeks.
  ///
  /// The current-day summary is not changed; only the week displayed in the
  /// history section and its cached records are updated.
  Future<void> _changeWeek(int amount) async {
    final nextWeek = _weekStart.add(Duration(days: amount * 7));
    setState(() {
      _weekStart = nextWeek;
      _isLoading = true;
    });
    try {
      final records = await _loadWeekRecords(nextWeek);
      if (!mounted) return;
      setState(() {
        _weekLogs = records;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Unable to load that week. Please try again.');
    }
  }

  /// Adds water to today's total and persists the increment in Firestore.
  ///
  /// Firestore's increment operation avoids overwriting a value with a stale
  /// client-side total. Reaching the daily target for the first time also
  /// triggers the health-goal points award.
  Future<void> _addWater(int amount) async {
    if (amount <= 0 || _isSaving) return;
    final previousValue = waterIntake;
    setState(() {
      waterIntake += amount;
      _isSaving = true;
    });

    try {
      await _dayDocument(_today).set({
        'date': _dateKey(_today),
        'waterIntake': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final reachedGoal = previousValue < waterGoal && waterIntake >= waterGoal;
      PointsAwardResult? pointsResult;
      var pointsSyncFailed = false;
      if (reachedGoal) {
        try {
          pointsResult = await _awardHealthGoal('water', 'Daily water goal');
        } catch (_) {
          pointsSyncFailed = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _weekLogs[_dateKey(_today)] = {
          ...?_weekLogs[_dateKey(_today)],
          'waterIntake': waterIntake,
        };
      });
      if (pointsSyncFailed) {
        _showMessage('Water saved, but points could not be synced.');
      } else if (pointsResult?.awarded == true) {
        _showMessage('Daily water goal reached! You earned ${pointsResult!.points} points.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        waterIntake = previousValue;
        _isSaving = false;
      });
      _showMessage('Water intake could not be saved. Please try again.');
    }
  }

  /// Resets today's water total to zero in both the UI and Firestore.
  ///
  /// The previous value is retained so the UI can be restored if the write
  /// fails. Resetting does not delete the day's other health information.
  Future<void> _resetWater() async {
    if (waterIntake == 0 || _isSaving) return;
    final previousValue = waterIntake;
    setState(() {
      waterIntake = 0;
      _isSaving = true;
    });

    try {
      await _dayDocument(_today).set({
        'date': _dateKey(_today),
        'waterIntake': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _weekLogs[_dateKey(_today)] = {
          ...?_weekLogs[_dateKey(_today)],
          'waterIntake': 0,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        waterIntake = previousValue;
        _isSaving = false;
      });
      _showMessage('Water intake could not be reset. Please try again.');
    }
  }

  /// Opens a dialog for entering the number of hours slept.
  ///
  /// The entry is associated with today's date (the date the user woke up).
  /// Input is validated before the dialog returns a value to be saved.
  Future<void> _logSleep() async {
    String sleepInput = sleepHours == 0 ? '' : _formatSleepInput(sleepHours);
    String? validationMessage;

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Sleep'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                initialValue: sleepInput,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onChanged: (value) {
                  sleepInput = value;
                  if (validationMessage != null) {
                    setDialogState(() => validationMessage = null);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Hours slept',
                  hintText: 'Example: 7.5',
                  suffixText: 'hours',
                  border: OutlineInputBorder(),
                ),
              ),
              if (validationMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  validationMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'This sleep entry is recorded for today, the date you woke up.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final hours = double.tryParse(sleepInput.trim());
                if (hours == null || !hours.isFinite || hours <= 0 || hours > 24) {
                  setDialogState(() {
                    validationMessage = 'Enter a number greater than 0 and no more than 24.';
                  });
                  return;
                }
                Navigator.pop(dialogContext, hours);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    final previousValue = sleepHours;
    setState(() {
      sleepHours = result;
      _isSaving = true;
    });

    try {
      await _dayDocument(_today).set({
        'date': _dateKey(_today),
        'sleepHours': result,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final reachedGoal = previousValue < sleepGoal && result >= sleepGoal;
      PointsAwardResult? pointsResult;
      var pointsSyncFailed = false;
      if (reachedGoal) {
        try {
          pointsResult = await _awardHealthGoal('sleep', 'Daily sleep goal');
        } catch (_) {
          pointsSyncFailed = true;
        }
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _weekLogs[_dateKey(_today)] = {
          ...?_weekLogs[_dateKey(_today)],
          'sleepHours': result,
        };
      });
      if (pointsSyncFailed) {
        _showMessage('Sleep entry saved, but points could not be synced.');
      } else if (pointsResult?.awarded == true) {
        _showMessage('Sleep entry saved. You earned ${pointsResult!.points} points!');
      } else {
        _showMessage('Sleep entry saved.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        sleepHours = previousValue;
        _isSaving = false;
      });
      _showMessage('Sleep could not be saved. Please try again.');
    }
  }

  /// Awards points for completing a daily health target.
  ///
  /// The date and goal identifier form the source ID, allowing the points
  /// service to recognize repeat attempts for the same goal on the same day.
  Future<PointsAwardResult?> _awardHealthGoal(String goalId, String title) {
    return PointsService.instance.awardActivity(
      type: PointsActivityType.healthGoal,
      sourceId: '${_dateKey(_today)}_$goalId',
      title: title,
      metadata: <String, dynamic>{
        'goalId': goalId,
        'date': _dateKey(_today),
      },
    );
  }

  // Avoid displaying unnecessary decimal places for whole-hour sleep entries.
  String _formatSleepInput(double hours) =>
      hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toString();

  // Display a short confirmation or error message at the bottom of the screen.
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Calculates the average of non-zero entries for a selected weekly metric.
  ///
  /// Days without a recorded value are excluded rather than counted as zero.
  double _averageFor(String field) {
    final values = _weekLogs.values
        .map((record) => (record[field] as num?)?.toDouble() ?? 0)
        .where((value) => value > 0)
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  // Count how many days in the selected week contain a positive value.
  int _daysLogged(String field) => _weekLogs.values
      .where((record) => ((record[field] as num?)?.toDouble() ?? 0) > 0)
      .length;

  /// Builds the health dashboard, including daily trackers and weekly history.
  ///
  /// Loading and error states are handled before the main content is created.
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadHealthData,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    // Progress indicators are capped at 100% so values above a goal do not
    // overflow their visual tracks. The underlying totals remain unchanged.
    final waterProgress = (waterIntake / waterGoal).clamp(0.0, 1.0).toDouble();
    final sleepProgress = (sleepHours / sleepGoal).clamp(0.0, 1.0).toDouble();
    final currentDate = DateFormat('EEEE, MMMM d').format(_today);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page heading and the date to which the current-day entries apply.
          Text(
            'Your Health',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 6),
          Text(currentDate, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
          if (_isSaving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 24),

          // Compact summary cards provide the current water and sleep totals.
          _buildSectionTitle('Daily Overview'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.water_drop,
                  title: 'Water',
                  value: _formatWater(waterIntake),
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.bedtime,
                  title: 'Sleep',
                  value: '${sleepHours.toStringAsFixed(1)} hrs',
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Hydration tracker: circular progress, quick-add control, and reset.
          _buildSectionTitle('Water Intake'),
          const SizedBox(height: 12),
          _buildTrackerCard(
            child: Column(
              children: [
                const Text('Your Daily Hydration', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 210,
                        height: 210,
                        child: CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 13,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade50),
                        ),
                      ),
                      SizedBox(
                        width: 210,
                        height: 210,
                        child: CircularProgressIndicator(
                          value: waterProgress,
                          strokeWidth: 13,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                          semanticsLabel: 'Daily water intake progress',
                          semanticsValue: '${(waterProgress * 100).round()} percent of goal',
                        ),
                      ),
                      SizedBox(
                        width: 145,
                        height: 145,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : () => _addWater(_waterIncrementMl),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade800,
                            elevation: 0,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.water_drop, size: 38),
                              const SizedBox(height: 5),
                              Text(_waterIncrementLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text('Add a cup', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(_formatWater(waterIntake), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue)),
                Text('of ${_formatWater(waterGoal)} daily goal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                const SizedBox(height: 16),
                Text(
                  waterIntake >= waterGoal ? 'Daily water goal reached!' : '${_formatWater(waterGoal - waterIntake)} remaining',
                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: waterIntake == 0 || _isSaving ? null : _resetWater,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset water intake'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Sleep tracker: shows the saved duration and progress toward the
          // daily target, with a dialog for entering or editing the duration.
          _buildSectionTitle('Sleep Tracking'),
          const SizedBox(height: 12),
          _buildTrackerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.bedtime, color: Colors.deepPurple, size: 38),
                const SizedBox(height: 12),
                const Text("Last Night's Sleep", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),
                Text('${sleepHours.toStringAsFixed(1)} hours', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: sleepProgress,
                    minHeight: 14,
                    backgroundColor: Colors.deepPurple.shade50,
                    color: Colors.deepPurple,
                    semanticsLabel: 'Sleep goal progress',
                    semanticsValue: '${(sleepProgress * 100).round()} percent of goal',
                  ),
                ),
                const SizedBox(height: 10),
                Text('Daily goal: ${sleepGoal.toStringAsFixed(0)} hours', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _logSleep,
                    icon: const Icon(Icons.edit),
                    label: Text(sleepHours == 0 ? 'Log Sleep Hours' : 'Edit Sleep Hours'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navigationNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Weekly chart and averages for the currently selected Monday-Sunday.
          _buildWeeklySection(),
          const SizedBox(height: 28),

          // Closing reminder displayed below the tracking tools.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface, borderRadius: BorderRadius.circular(16)),
            child: const Row(
              children: [
                Icon(Icons.favorite, color: Colors.white, size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Small healthy habits make a big difference. Keep taking care of yourself!',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Builds the weekly history card, including week navigation, averages,
  /// logged-day counts, and daily bar charts for water and sleep.
  Widget _buildWeeklySection() {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final weekLabel = '${DateFormat('MMM d').format(_weekStart)} – ${DateFormat('MMM d, y').format(weekEnd)}';
    final averageWater = _averageFor('waterIntake');
    final averageSleep = _averageFor('sleepHours');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Weekly Progress'),
        const SizedBox(height: 12),
        _buildTrackerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Previous/next controls change the displayed week. Future weeks
              // are disabled so users cannot navigate beyond the current week.
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous week',
                    onPressed: () => _changeWeek(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(child: Text(weekLabel, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(
                    tooltip: 'Next week',
                    onPressed: _weekStart.isBefore(_mondayOf(DateTime.now())) ? () => _changeWeek(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Averages and logged-day counts exclude days with no entry.
              Row(
                children: [
                  Expanded(child: _buildWeeklyAverage('Avg. water', _formatWater(averageWater.round()), '${_daysLogged('waterIntake')} days logged', Colors.blue)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildWeeklyAverage('Avg. sleep', '${averageSleep.toStringAsFixed(1)} hrs', '${_daysLogged('sleepHours')} nights logged', Colors.deepPurple)),
                ],
              ),
              const SizedBox(height: 22),
              Text('Water intake ($_waterUnit)', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildWeeklyBars('waterIntake', waterGoal, Colors.blue, 'water'),
              const SizedBox(height: 22),
              const Text('Sleep', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildWeeklyBars('sleepHours', sleepGoal, Colors.deepPurple, 'hrs'),
              const SizedBox(height: 8),
              Text(
                'Averages use days with an entry. Empty days are not counted as zero.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds one of the small metric cards used for weekly averages.
  Widget _buildWeeklyAverage(String title, String value, String detail, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(detail, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
        ],
      ),
    );
  }

  /// Draws seven vertical bars, one for each day in the selected week.
  ///
  /// [field] identifies the Firestore metric, [goal] sets the full-scale
  /// height, [color] styles recorded values, and [unit] controls value labels.
  Widget _buildWeeklyBars(String field, num goal, Color color, String unit) {
    final goalValue = goal.toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (index) {
        final date = _weekStart.add(Duration(days: index));
        final value = (_weekLogs[_dateKey(date)]?[field] as num?)?.toDouble() ?? 0;
        final progress = (value / goalValue).clamp(0.0, 1.0).toDouble();
        final barHeight = value <= 0 ? 3.0 : 82.0 * progress;
        return Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 90,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 18,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: value <= 0 ? Theme.of(context).colorScheme.surfaceContainerHighest : color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(DateFormat('E').format(date), style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Text(
                value <= 0
                    ? '—'
                    : unit == 'water'
                        ? _displayWater(value.round()).round().toString()
                        : value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      }),
    );
  }

  // Shared heading style keeps section labels consistent across the page.
  Widget _buildSectionTitle(String title) => Text(
        title,
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
      );

  /// Builds a compact card for one of the daily overview values.
  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Shared surface styling for the larger hydration, sleep, and weekly cards.
  Widget _buildTrackerCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );
}
