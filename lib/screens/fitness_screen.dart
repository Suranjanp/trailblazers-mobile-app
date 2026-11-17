// ignore_for_file: avoid_types_as_parameter_names

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/health_connect_service.dart';

class FitnessScreen extends StatefulWidget {
  const FitnessScreen({super.key});

  @override
  State<FitnessScreen> createState() => _FitnessScreenState();
}

class _FitnessScreenState extends State<FitnessScreen> {
  static const List<String> _workoutTypes = [
    'Walking',
    'Running',
    'Cycling',
    'Strength training',
    'Swimming',
    'Yoga',
    'Hiking',
    'HIIT',
    'Other',
  ];

  User? get _user => FirebaseAuth.instance.currentUser;

  Timer? _ticker;
  final HealthConnectService _healthService = HealthConnectService();
  bool _healthReady = false;
  bool _healthAvailable = false;
  bool _healthConnected = false;
  bool _isConnectingHealth = false;
  bool _isRefreshingHealth = false;
  int? _todaySteps;
  double? _todayWalkingDistanceKm;
  DateTime? _healthLastUpdated;
  String? _healthMessage;
  String? _activeWorkoutId;
  Map<String, dynamic>? _activeWorkout;
  DateTime? _activeStartedAt;
  int _elapsedSeconds = 0;
  bool _isStarting = false;
  bool _isFinishing = false;
  String? _loadError;

  CollectionReference<Map<String, dynamic>> get _workouts {
    final user = _user;
    if (user == null) {
      throw StateError('You must be signed in to track workouts.');
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('workout_sessions');
  }

  @override
  void initState() {
    super.initState();
    _restoreActiveWorkout();
    _initializeHealthConnect();
  }

  Future<void> _initializeHealthConnect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        setState(() {
          _healthReady = true;
          _healthMessage = 'Automatic health syncing is currently available on Android.';
        });
      }
      return;
    }

    try {
      await _healthService.initialize();
      final available = await _healthService.isAvailable();
      final hasAccess = available && await _healthService.hasReadAccess();
      if (!mounted) return;

      setState(() {
        _healthReady = true;
        _healthAvailable = available;
        _healthConnected = hasAccess;
        _healthMessage = available
            ? (hasAccess ? null : 'Connect Health Connect to show your real activity.')
            : 'Install or update Health Connect to connect your activity data.';
      });

      if (hasAccess) {
        await _refreshHealthMetrics(showErrors: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _healthReady = true;
        _healthAvailable = false;
        _healthMessage = 'Health Connect could not be initialized on this device.';
      });
    }
  }

  Future<void> _connectHealthConnect() async {
    if (_isConnectingHealth || _isRefreshingHealth) return;
    setState(() => _isConnectingHealth = true);

    try {
      final granted = await _healthService.requestReadAccess();
      if (!mounted) return;

      if (!granted) {
        setState(() {
          _isConnectingHealth = false;
          _healthConnected = false;
          _healthMessage = 'Health data access was not granted. You can try again at any time.';
        });
        return;
      }

      setState(() {
        _isConnectingHealth = false;
        _healthConnected = true;
        _healthMessage = null;
      });
      await _refreshHealthMetrics();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isConnectingHealth = false;
        _healthMessage = error.toString().replaceFirst('Bad state: ', '');
      });
      _showMessage(_healthMessage!);
    }
  }

  Future<void> _refreshHealthMetrics({bool showErrors = true}) async {
    if (_isRefreshingHealth) return;
    setState(() => _isRefreshingHealth = true);

    try {
      final metrics = await _healthService.readToday();
      if (!mounted) return;
      setState(() {
        _todaySteps = metrics.steps;
        _todayWalkingDistanceKm = metrics.walkingDistanceKm;
        _healthLastUpdated = metrics.measuredAt;
        _healthConnected = true;
        _isRefreshingHealth = false;
        _healthMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRefreshingHealth = false;
        _healthConnected = false;
        _healthMessage = error.toString().replaceFirst('Bad state: ', '');
      });
      if (showErrors) _showMessage(_healthMessage!);
    }
  }


  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restoreActiveWorkout() async {
    if (_user == null) {
      if (mounted) setState(() => _loadError = 'Sign in to save and view workouts.');
      return;
    }

    try {
      final result = await _workouts
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (!mounted || result.docs.isEmpty) return;

      final doc = result.docs.first;
      final data = doc.data();
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      if (startedAt == null) return;

      setState(() {
        _activeWorkoutId = doc.id;
        _activeWorkout = data;
        _activeStartedAt = startedAt;
        _elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      });
      _startTicker();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError = 'Could not load your workout. Check your connection and retry.';
        });
      }
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _activeStartedAt;
      if (startedAt == null || !mounted) return;
      setState(() {
        _elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      });
    });
  }

  Future<void> _startWorkout(String type) async {
    if (_isStarting || _activeWorkoutId != null) return;
    setState(() => _isStarting = true);

    try {
      final startedAt = DateTime.now();
      final doc = await _workouts.add({
        'type': type,
        'status': 'active',
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': null,
        'durationSeconds': 0,
        'distanceKm': null,
        'calories': null,
        'notes': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _activeWorkoutId = doc.id;
        _activeWorkout = {'type': type};
        _activeStartedAt = startedAt;
        _elapsedSeconds = 0;
        _isStarting = false;
        _loadError = null;
      });
      _startTicker();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      _showMessage('Workout could not be started. Please try again.');
    }
  }

  Future<void> _finishWorkout() async {
    final id = _activeWorkoutId;
    final startedAt = _activeStartedAt;
    if (id == null || startedAt == null || _isFinishing) return;

    final distanceController = TextEditingController();
    final caloriesController = TextEditingController();
    final notesController = TextEditingController();
    final type = (_activeWorkout?['type'] as String?) ?? 'Workout';

    final result = await showDialog<_WorkoutFinishDetails>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finish workout'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('You completed ${_formatDuration(_elapsedSeconds)} of $type.'),
              const SizedBox(height: 16),
              TextField(
                controller: distanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Distance (optional)',
                  suffixText: 'km',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: caloriesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Calories (optional)',
                  suffixText: 'kcal',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep working out'),
          ),
          FilledButton(
            onPressed: () {
              final distanceText = distanceController.text.trim();
              final caloriesText = caloriesController.text.trim();
              final distance = distanceText.isEmpty ? null : double.tryParse(distanceText);
              final calories = caloriesText.isEmpty ? null : int.tryParse(caloriesText);

              if ((distanceText.isNotEmpty &&
                      (distance == null || !distance.isFinite || distance < 0)) ||
                  (caloriesText.isNotEmpty && (calories == null || calories < 0))) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter valid non-negative distance and calorie values.')),
                );
                return;
              }

              Navigator.pop(
                dialogContext,
                _WorkoutFinishDetails(
                  distanceKm: distance,
                  calories: calories,
                  notes: notesController.text.trim(),
                ),
              );
            },
            child: const Text('Save workout'),
          ),
        ],
      ),
    );

    distanceController.dispose();
    caloriesController.dispose();
    notesController.dispose();

    if (result == null || !mounted) return;

    setState(() => _isFinishing = true);
    _ticker?.cancel();

    final endedAt = DateTime.now();
    final duration = endedAt.difference(startedAt).inSeconds;

    try {
      await _workouts.doc(id).update({
        'status': 'completed',
        'endedAt': Timestamp.fromDate(endedAt),
        'durationSeconds': duration,
        'distanceKm': result.distanceKm,
        'calories': result.calories,
        'notes': result.notes,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _activeWorkoutId = null;
        _activeWorkout = null;
        _activeStartedAt = null;
        _elapsedSeconds = 0;
        _isFinishing = false;
      });
      _showMessage('Workout saved.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFinishing = false);
      _startTicker();
      _showMessage('Workout could not be saved. Your timer is still running.');
    }
  }

  Future<void> _showStartWorkoutSheet() async {
    if (_activeWorkoutId != null || _isStarting) return;

    final selectedType = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a workout', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _workoutTypes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (context, index) {
                  final type = _workoutTypes[index];
                  return OutlinedButton(
                    onPressed: () => Navigator.pop(context, type),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_iconFor(type), size: 25),
                        const SizedBox(height: 6),
                        Text(type, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedType != null && mounted) {
      await _startWorkout(selectedType);
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'Walking':
        return Icons.directions_walk;
      case 'Running':
        return Icons.directions_run;
      case 'Cycling':
        return Icons.directions_bike;
      case 'Strength training':
        return Icons.fitness_center;
      case 'Swimming':
        return Icons.pool;
      case 'Yoga':
        return Icons.self_improvement;
      case 'Hiking':
        return Icons.terrain;
      case 'HIIT':
        return Icons.bolt;
      default:
        return Icons.sports;
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = _user;

    if (user == null) {
      return const Center(child: Text('Please sign in to use fitness tracking.'));
    }

    final recentWorkouts = _workouts
        .where(
          'startedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 30)),
          ),
        )
        .orderBy('startedAt', descending: true)
        .limit(50);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR ACTIVITY', style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          )),
          const SizedBox(height: 5),
          Text('Fitness', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),

          if (_loadError != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(_loadError!),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _restoreActiveWorkout,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          _buildHealthConnectCard(context),
          const SizedBox(height: 14),

          if (_activeWorkoutId != null)
            _buildActiveWorkoutCard(context)
          else
            _buildStartWorkoutCard(context),

          const SizedBox(height: 22),
          Text('Workout activity', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: recentWorkouts.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Could not load workout history. Check your Firestore rules and connection.'),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ));
              }

              final docs = snapshot.data?.docs ?? [];
              final completed = docs.where((doc) => doc.data()['status'] == 'completed').toList();
              final totalSeconds = completed.fold<int>(
                0,
                (sum, doc) => sum + ((doc.data()['durationSeconds'] as num?)?.toInt() ?? 0),
              );
              final totalDistance = completed.fold<double>(
                0,
                (sum, doc) => sum + ((doc.data()['distanceKm'] as num?)?.toDouble() ?? 0),
              );

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _summaryCard(context, Icons.fitness_center, 'Sessions', '${completed.length}')),
                      const SizedBox(width: 10),
                      Expanded(child: _summaryCard(context, Icons.timer_outlined, 'Time', _formatDuration(totalSeconds))),
                      const SizedBox(width: 10),
                      Expanded(child: _summaryCard(context, Icons.route_outlined, 'Distance', '${totalDistance.toStringAsFixed(1)} km')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (completed.isEmpty)
                    Card(
                      elevation: 0,
                      color: colors.surfaceContainerLow,
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.directions_run, size: 34),
                              SizedBox(height: 8),
                              Text('No completed workouts yet', style: TextStyle(fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Start a workout and it will appear here.', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ...completed.take(10).map((doc) => _workoutTile(context, doc.data())),
                ],
              );
            },
          ),

          const SizedBox(height: 22),
          _buildComingSoonCard(context),
        ],
      ),
    );
  }

  Widget _buildHealthConnectCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final supported = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final progress = (_todaySteps ?? 0) / 10000;
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();

    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety_outlined, color: colors.primary, size: 25),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Daily health data',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_healthConnected)
                  Icon(Icons.check_circle, color: colors.primary, size: 21),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              supported
                  ? 'Read your steps and walking distance from Android Health Connect.'
                  : 'Automatic health syncing is not configured for this platform yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (_healthConnected && _todaySteps != null) ...[
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _healthMetric(
                      context,
                      icon: Icons.directions_walk_rounded,
                      label: 'Steps today',
                      value: NumberFormat.decimalPattern().format(_todaySteps),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _healthMetric(
                      context,
                      icon: Icons.route_rounded,
                      label: 'Walking distance',
                      value: '${(_todayWalkingDistanceKm ?? 0).toStringAsFixed(2)} km',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: clampedProgress,
                  minHeight: 9,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(clampedProgress * 100).round()}% of a 10,000-step reference goal',
                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (_healthLastUpdated != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Updated ${DateFormat('h:mm a').format(_healthLastUpdated!)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ] else if (_healthMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _healthMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: !supported || !_healthReady || _isConnectingHealth || _isRefreshingHealth
                    ? null
                    : (_healthConnected ? _refreshHealthMetrics : _connectHealthConnect),
                icon: (_isConnectingHealth || _isRefreshingHealth)
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_healthConnected ? Icons.refresh : Icons.link),
                label: Text(
                  !_healthReady
                      ? 'Checking availability...'
                      : _isConnectingHealth
                          ? 'Connecting...'
                          : _isRefreshingHealth
                              ? 'Refreshing...'
                              : _healthConnected
                                  ? 'Refresh health data'
                                  : 'Connect Health Connect',
                ),
              ),
            ),
            if (supported && _healthReady && !_healthAvailable && !_healthConnected) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _isConnectingHealth
                      ? null
                      : () async {
                          try {
                            await _healthService.installOrUpdateHealthConnect();
                          } catch (_) {
                            _showMessage('Could not open the Health Connect installation page.');
                          }
                        },
                  child: const Text('Install or update Health Connect'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _healthMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.primary, size: 21),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildStartWorkoutCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.play_circle_fill_rounded, size: 34, color: colors.onPrimaryContainer),
            const SizedBox(height: 12),
            Text('Ready to move?', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            )),
            const SizedBox(height: 5),
            Text('Start a workout and track your time, distance, and notes.',
              style: TextStyle(color: colors.onPrimaryContainer)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isStarting ? null : _showStartWorkoutSheet,
                icon: _isStarting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_isStarting ? 'Starting...' : 'Start a workout'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveWorkoutCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = (_activeWorkout?['type'] as String?) ?? 'Workout';
    return Card(
      elevation: 0,
      color: colors.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(type), color: colors.onSecondaryContainer, size: 27),
                const SizedBox(width: 10),
                Expanded(child: Text('$type in progress', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ))),
                const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                _formatDuration(_elapsedSeconds),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isFinishing ? null : _finishWorkout,
                icon: const Icon(Icons.stop),
                label: Text(_isFinishing ? 'Saving...' : 'Finish workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context, IconData icon, String title, String value) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(height: 7),
            Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(title, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _workoutTile(BuildContext context, Map<String, dynamic> data) {
    final type = (data['type'] as String?) ?? 'Workout';
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final duration = (data['durationSeconds'] as num?)?.toInt() ?? 0;
    final distance = (data['distanceKm'] as num?)?.toDouble();
    final calories = (data['calories'] as num?)?.toInt();
    final details = <String>[
      _formatDuration(duration),
      if (distance != null) '${distance.toStringAsFixed(2)} km',
      if (calories != null) '$calories kcal',
    ].join(' · ');

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(_iconFor(type), color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${startedAt == null ? '' : DateFormat('MMM d · h:mm a').format(startedAt)}\n$details'),
        isThreeLine: true,
        trailing: const Icon(Icons.check_circle_outline),
      ),
    );
  }

  Widget _buildComingSoonCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('More fitness tracking', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const _FeatureRow(icon: Icons.directions_walk, title: 'Automatic step tracking', subtitle: 'Connect Android Health Connect or Apple Health'),
            const _FeatureRow(icon: Icons.map_outlined, title: 'GPS workout routes', subtitle: 'Map distance, pace, and elevation'),
            const _FeatureRow(icon: Icons.fitness_center, title: 'Strength training', subtitle: 'Log exercises, sets, reps, and weight'),
            const _FeatureRow(icon: Icons.emoji_events_outlined, title: 'Goals and personal records', subtitle: 'Build consistency and track milestones'),
          ],
        ),
      ),
    );
  }
}

class _WorkoutFinishDetails {
  const _WorkoutFinishDetails({
    required this.distanceKm,
    required this.calories,
    required this.notes,
  });

  final double? distanceKm;
  final int? calories;
  final String notes;
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
