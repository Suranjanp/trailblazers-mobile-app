// ignore_for_file: avoid_types_as_parameter_names

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

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
  final ValueNotifier<int> _elapsedSecondsNotifier = ValueNotifier<int>(0);
  DateTime? _pausedAt;
  int _totalPausedSeconds = 0;
  bool _isWorkoutPaused = false;
  bool _isStarting = false;
  bool _isFinishing = false;
  String? _loadError;
  String _selectedTrainingLevel = 'Beginner';
  String _fitnessTab = 'Train';
  String _gpsHistoryFilter = 'All';
  StreamSubscription<Position>? _gpsSubscription;
  final List<Map<String, dynamic>> _gpsRoutePoints = [];
  double _gpsDistanceMeters = 0;
  double _gpsElevationGainMeters = 0;
  Position? _lastGpsPosition;
  Position? _currentGpsPosition;
  bool _gpsStarting = false;
  int _gpsPointsSinceSave = 0;
  String? _gpsStatusMessage;

  CollectionReference<Map<String, dynamic>> get _customWorkouts {
    final user = _user;
    if (user == null) {
      throw StateError('You must be signed in to save custom workouts.');
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('custom_workouts');
  }

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

  DocumentReference<Map<String, dynamic>> get _fitnessProfile {
    final user = _user;
    if (user == null) {
      throw StateError('You must be signed in to manage fitness goals.');
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('fitness_profile')
        .doc('current');
  }

  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
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
    _gpsSubscription?.cancel();
    _elapsedSecondsNotifier.dispose();
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
      final pausedAt = (data['pausedAt'] as Timestamp?)?.toDate();
      final totalPausedSeconds = (data['totalPausedSeconds'] as num?)?.toInt() ?? 0;
      final currentPause = pausedAt == null ? 0 : DateTime.now().difference(pausedAt).inSeconds;

      setState(() {
        _activeWorkoutId = doc.id;
        _activeWorkout = data;
        _activeStartedAt = startedAt;
        _pausedAt = pausedAt;
        _totalPausedSeconds = totalPausedSeconds;
        _isWorkoutPaused = pausedAt != null;
        _elapsedSeconds = (DateTime.now().difference(startedAt).inSeconds - totalPausedSeconds - currentPause).clamp(0, 1 << 30).toInt();
        _gpsDistanceMeters = (data['gpsDistanceMeters'] as num?)?.toDouble() ?? 0;
        _gpsElevationGainMeters = (data['gpsElevationGainMeters'] as num?)?.toDouble() ?? 0;
        _gpsRoutePoints
          ..clear()
          ..addAll((data['routePoints'] as List<dynamic>? ?? const []).whereType<Map>().map((point) => Map<String, dynamic>.from(point)));
      });
      _elapsedSecondsNotifier.value = _elapsedSeconds;
      _startTicker();
      if (data['gpsTracking'] == true && pausedAt == null) {
        _startGpsLocationStream();
      }
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
      final currentPause = _pausedAt == null ? 0 : DateTime.now().difference(_pausedAt!).inSeconds;
      final nextElapsed = (DateTime.now().difference(startedAt).inSeconds - _totalPausedSeconds - currentPause).clamp(0, 1 << 30).toInt();
      if (nextElapsed != _elapsedSeconds) {
        _elapsedSeconds = nextElapsed;
        // Update only the timer display; avoid rebuilding the entire fitness screen.
        _elapsedSecondsNotifier.value = nextElapsed;
      }
    });
  }

  Future<void> _startGpsActivity(String activity) async {
    if (_gpsStarting || _activeWorkoutId != null) return;
    setState(() {
      _gpsStarting = true;
      _gpsStatusMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _gpsStarting = false;
            _gpsStatusMessage = 'Turn on device location to start GPS tracking.';
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _gpsStarting = false;
            _gpsStatusMessage = permission == LocationPermission.deniedForever
                ? 'Location permission is blocked. Enable it in Android app settings.'
                : 'Location permission is required for GPS activity tracking.';
          });
        }
        return;
      }

      _gpsRoutePoints.clear();
      _gpsDistanceMeters = 0;
      _gpsElevationGainMeters = 0;
      _lastGpsPosition = null;
      _currentGpsPosition = null;
      _gpsPointsSinceSave = 0;
      await _startWorkout(activity, sessionData: {
        'gpsTracking': true,
        'activityMode': activity,
        'gpsDistanceMeters': 0.0,
        'routePoints': <Map<String, dynamic>>[],
      });

      if (!mounted) return;
      if (_activeWorkoutId != null && _activeWorkout?['gpsTracking'] == true) {
        setState(() => _gpsStarting = false);
        await _startGpsLocationStream();
      } else {
        setState(() => _gpsStarting = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _gpsStarting = false;
        _gpsStatusMessage = 'GPS could not start: ${error.toString()}';
      });
    }
  }

  Future<void> _startGpsLocationStream() async {
    if (_activeWorkout?['gpsTracking'] != true || _isWorkoutPaused) return;
    await _gpsSubscription?.cancel();
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted || _activeWorkoutId == null || _isWorkoutPaused) return;
      _acceptGpsPosition(current);
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        _acceptGpsPosition,
        onError: (Object error) {
          if (mounted) {
            setState(() => _gpsStatusMessage = 'GPS signal interrupted. Check location settings.');
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _gpsStatusMessage = 'Waiting for a reliable GPS signal.');
      }
    }
  }

  void _acceptGpsPosition(Position position) {
    if (!mounted || _activeWorkoutId == null || _isWorkoutPaused) return;
    if (position.accuracy > 50) return;

    final previous = _lastGpsPosition;
    if (previous != null) {
      final segment = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      // Ignore implausible GPS jumps rather than inflating distance/elevation.
      if (segment < 250) {
        _gpsDistanceMeters += segment;
        final elevationChange = position.altitude - previous.altitude;
        // GPS altitude is noisy; count only meaningful uphill changes.
        if (elevationChange > 1.5 && elevationChange < 30) {
          _gpsElevationGainMeters += elevationChange;
        }
      }
    }

    _lastGpsPosition = position;
    _currentGpsPosition = position;
    _gpsRoutePoints.add({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'cumulativeDistanceMeters': _gpsDistanceMeters,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
    });
    // Keep the Firestore route payload bounded for long activities.
    if (_gpsRoutePoints.length > 1000) {
      for (var i = _gpsRoutePoints.length - 2; i > 0; i -= 2) {
        _gpsRoutePoints.removeAt(i);
      }
    }
    _gpsPointsSinceSave++;
    if (mounted) setState(() => _gpsStatusMessage = null);

    if (_gpsPointsSinceSave >= 20) {
      _gpsPointsSinceSave = 0;
      final id = _activeWorkoutId;
      if (id != null) {
        _workouts.doc(id).update({
          'gpsDistanceMeters': _gpsDistanceMeters,
          'gpsElevationGainMeters': _gpsElevationGainMeters,
          'routePoints': _gpsRoutePoints,
          'gpsSplits': _calculateGpsSplits(_gpsRoutePoints),
          'updatedAt': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      }
    }
  }

  List<Map<String, dynamic>> _calculateGpsSplits(List<Map<String, dynamic>> points) {
    if (points.length < 2) return [];
    final splits = <Map<String, dynamic>>[];
    var cumulative = 0.0;
    var nextSplitAt = 1000.0;
    int? previousTimestamp;
    int? splitStartTimestamp;
    double? previousLatitude;
    double? previousLongitude;
    double? previousCumulative;

    for (final point in points) {
      final latitude = (point['latitude'] as num?)?.toDouble();
      final longitude = (point['longitude'] as num?)?.toDouble();
      final timestamp = (point['timestamp'] as num?)?.toInt();
      if (latitude == null || longitude == null || timestamp == null) continue;

      if (previousTimestamp == null) {
        previousTimestamp = timestamp;
        splitStartTimestamp = timestamp;
        previousLatitude = latitude;
        previousLongitude = longitude;
        previousCumulative = (point['cumulativeDistanceMeters'] as num?)?.toDouble() ?? 0;
        continue;
      }

      final storedCumulative = (point['cumulativeDistanceMeters'] as num?)?.toDouble();
      if (storedCumulative != null && previousCumulative != null) {
        cumulative = storedCumulative;
      } else {
        cumulative += Geolocator.distanceBetween(previousLatitude!, previousLongitude!, latitude, longitude);
      }

      final oldDistance = previousCumulative ?? (cumulative - Geolocator.distanceBetween(previousLatitude!, previousLongitude!, latitude, longitude));
      final segmentDistance = cumulative - oldDistance;
      final elapsedBetween = (timestamp - previousTimestamp).clamp(0, 3600000);
      while (cumulative >= nextSplitAt && segmentDistance > 0) {
        final fraction = ((nextSplitAt - oldDistance) / segmentDistance).clamp(0.0, 1.0);
        final crossingTime = previousTimestamp + (elapsedBetween * fraction).round();
        final startTime = splitStartTimestamp ?? previousTimestamp;
        splits.add({
          'split': splits.length + 1,
          'distanceKm': 1.0,
          'durationSeconds': ((crossingTime - startTime) / 1000).round().clamp(0, 86400),
        });
        splitStartTimestamp = crossingTime;
        nextSplitAt += 1000;
      }
      previousTimestamp = timestamp;
      previousLatitude = latitude;
      previousLongitude = longitude;
      previousCumulative = cumulative;
    }

    final finalTimestamp = (points.last['timestamp'] as num?)?.toInt();
    final finalDistance = (points.last['cumulativeDistanceMeters'] as num?)?.toDouble() ?? cumulative;
    final remainingMeters = finalDistance - ((splits.length) * 1000.0);
    if (finalTimestamp != null && splitStartTimestamp != null && remainingMeters >= 200) {
      splits.add({
        'split': splits.length + 1,
        'distanceKm': remainingMeters / 1000,
        'durationSeconds': ((finalTimestamp - splitStartTimestamp) / 1000).round().clamp(0, 86400),
      });
    }
    return splits;
  }

  String _formatGpsDistance() {
    final km = _gpsDistanceMeters / 1000;
    return km < 1
        ? '${_gpsDistanceMeters.toStringAsFixed(0)} m'
        : '${km.toStringAsFixed(2)} km';
  }

  Future<void> _startWorkout(String type, {Map<String, dynamic> sessionData = const {}}) async {
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
        ...sessionData,
        'currentExerciseIndex': 0,
        'exerciseLogs': <Map<String, dynamic>>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _activeWorkoutId = doc.id;
        _activeWorkout = {'type': type, ...sessionData, 'currentExerciseIndex': 0, 'exerciseLogs': <Map<String, dynamic>>[]};
        _activeStartedAt = startedAt;
        _elapsedSeconds = 0;
        _pausedAt = null;
        _totalPausedSeconds = 0;
        _isWorkoutPaused = false;
        _isStarting = false;
        _loadError = null;
      });
      _elapsedSecondsNotifier.value = _elapsedSeconds;
      _startTicker();

      // Planned workouts should enter guided mode immediately after the
      // session is successfully created. Basic/manual workouts remain on
      // the fitness screen.
      final plannedExerciseIds = sessionData['plannedExerciseIds'];
      if (plannedExerciseIds is List && plannedExerciseIds.isNotEmpty && mounted) {
        await _openGuidedWorkout();
      }
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

    final distanceController = TextEditingController(
      text: _activeWorkout?['gpsTracking'] == true && _gpsDistanceMeters > 0
          ? (_gpsDistanceMeters / 1000).toStringAsFixed(3)
          : '',
    );
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
    final currentPause = _pausedAt == null ? 0 : endedAt.difference(_pausedAt!).inSeconds;
    final duration = (endedAt.difference(startedAt).inSeconds - _totalPausedSeconds - currentPause).clamp(0, 1 << 30).toInt();

    try {
      await _gpsSubscription?.cancel();
      _gpsSubscription = null;
      await _workouts.doc(id).update({
        'status': 'completed',
        'pausedAt': null,
        'endedAt': Timestamp.fromDate(endedAt),
        'durationSeconds': duration,
        'distanceKm': result.distanceKm ?? (_activeWorkout?['gpsTracking'] == true ? _gpsDistanceMeters / 1000 : null),
        'calories': result.calories,
        if (_activeWorkout?['gpsTracking'] == true) ...{
          'gpsDistanceMeters': _gpsDistanceMeters,
          'gpsElevationGainMeters': _gpsElevationGainMeters,
          'routePoints': _gpsRoutePoints,
          'gpsSplits': _calculateGpsSplits(_gpsRoutePoints),
        },
        'notes': result.notes,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _activeWorkoutId = null;
        _activeWorkout = null;
        _activeStartedAt = null;
        _elapsedSeconds = 0;
        _pausedAt = null;
        _totalPausedSeconds = 0;
        _isWorkoutPaused = false;
        _isFinishing = false;
        _gpsDistanceMeters = 0;
        _gpsElevationGainMeters = 0;
        _gpsRoutePoints.clear();
        _lastGpsPosition = null;
        _currentGpsPosition = null;
        _gpsStatusMessage = null;
      });
      _elapsedSecondsNotifier.value = _elapsedSeconds;
      _showMessage('Workout saved.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFinishing = false);
      _startTicker();
      if (_activeWorkout?['gpsTracking'] == true && !_isWorkoutPaused) {
        await _startGpsLocationStream();
      }
      _showMessage('Workout could not be saved. Your timer and GPS tracking are still running.');
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
              ConstrainedBox(
                // Keep the picker within the available screen height. On
                // smaller screens or with larger text, the options scroll
                // instead of overflowing the bottom sheet.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.52,
                ),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
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
      case 'Strength':
        return Icons.fitness_center;
      case 'Swimming':
        return Icons.pool;
      case 'Yoga':
        return Icons.self_improvement;
      case 'Hiking':
        return Icons.terrain;
      case 'HIIT':
      case 'Conditioning':
        return Icons.bolt;
      case 'Cardio':
        return Icons.directions_run;
      case 'Mobility':
        return Icons.self_improvement;
      case 'Custom workout':
        return Icons.playlist_add_check;
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

          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Train', label: Text('Train'), icon: Icon(Icons.fitness_center)),
              ButtonSegment(value: 'History', label: Text('History'), icon: Icon(Icons.history)),
            ],
            selected: {_fitnessTab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() => _fitnessTab = selection.first),
            expandedInsets: EdgeInsets.zero,
          ),
          const SizedBox(height: 14),
          if (_fitnessTab == 'Train') ...[
            _buildPersonalTrainingSection(context),
            const SizedBox(height: 18),
            _buildTrainingProgramsSection(context),
            const SizedBox(height: 18),
            _buildExerciseLibrarySection(context),
            const SizedBox(height: 18),
            _buildCustomWorkoutsSection(context),
            const SizedBox(height: 14),
            if (_activeWorkoutId == null) _buildGpsActivityCard(context),
            if (_activeWorkoutId != null)
              _buildActiveWorkoutCard(context)
            else
              _buildStartWorkoutCard(context),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text('Workout history', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                OutlinedButton.icon(
                  onPressed: _showTrainingCoachOverlay,
                  icon: const Icon(Icons.sports, size: 17),
                  label: const Text('Trainer'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: recentWorkouts.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Card(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Could not load workout history. Check your Firestore rules and connection.'),
                  ));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(24), child: CircularProgressIndicator(),
                  ));
                }
                final docs = snapshot.data?.docs ?? [];
                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);
                final today = docs.where((doc) {
                  final data = doc.data();
                  final started = data['startedAt'];
                  final date = started is Timestamp ? started.toDate() : started is DateTime ? started : null;
                  return data['status'] == 'completed' && date != null && !date.isBefore(todayStart) && date.isBefore(todayStart.add(const Duration(days: 1)));
                }).toList();
                final totalSeconds = today.fold<int>(0, (sum, doc) => sum + ((doc.data()['durationSeconds'] as num?)?.toInt() ?? 0));
                final totalDistance = today.fold<double>(0, (sum, doc) => sum + ((doc.data()['distanceKm'] as num?)?.toDouble() ?? 0));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's workouts", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _summaryCard(context, Icons.fitness_center, 'Sessions', '${today.length}')),
                      const SizedBox(width: 8),
                      Expanded(child: _summaryCard(context, Icons.timer_outlined, 'Time', _formatDuration(totalSeconds))),
                      const SizedBox(width: 8),
                      Expanded(child: _summaryCard(context, Icons.route_outlined, 'Distance', '${totalDistance.toStringAsFixed(1)} km')),
                    ]),
                    const SizedBox(height: 10),
                    if (today.isEmpty)
                      Card(elevation: 0, color: colors.surfaceContainerLow, child: const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: Text('No completed workouts today yet.')),
                      ))
                    else
                      ...today.take(10).map((doc) => _workoutTile(context, doc.data())),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _buildGpsRouteHistorySection(context),
            const SizedBox(height: 18),
            _buildGpsGoalsAndStatsSection(context),
            const SizedBox(height: 18),
            _buildTrainingInsightsSection(context),
            const SizedBox(height: 18),
            _buildPersonalRecordsSection(context),
            const SizedBox(height: 18),
            _buildPerformanceTrendsSection(context),
          ],

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

  Widget _buildGpsActivityCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gps_fixed, color: colors.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('GPS activity tracking', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const Text('LIVE GPS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 6),
            Text('Track your route and distance for outdoor activities.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _gpsActivityButton(context, 'Walking', Icons.directions_walk)),
                const SizedBox(width: 8),
                Expanded(child: _gpsActivityButton(context, 'Running', Icons.directions_run)),
                const SizedBox(width: 8),
                Expanded(child: _gpsActivityButton(context, 'Cycling', Icons.directions_bike)),
              ],
            ),
            if (_gpsStarting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 5),
              const Text('Preparing GPS activity…', style: TextStyle(fontSize: 12)),
            ],
            if (_gpsStatusMessage != null) ...[
              const SizedBox(height: 10),
              Text(_gpsStatusMessage!, style: TextStyle(color: colors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gpsActivityButton(BuildContext context, String activity, IconData icon) {
    return FilledButton.tonal(
      onPressed: _gpsStarting || _isStarting ? null : () => _startGpsActivity(activity),
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 4),
          Text(activity, style: const TextStyle(fontSize: 11)),
        ],
      ),
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

  Future<void> _setWorkoutPaused(bool pause) async {
    final id = _activeWorkoutId;
    if (id == null || pause == _isWorkoutPaused) return;
    final now = DateTime.now();
    final nextTotal = pause
        ? _totalPausedSeconds
        : _totalPausedSeconds + (_pausedAt == null ? 0 : now.difference(_pausedAt!).inSeconds);
    try {
      await _workouts.doc(id).update({
        'pausedAt': pause ? Timestamp.fromDate(now) : null,
        'totalPausedSeconds': nextTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _pausedAt = pause ? now : null;
        _totalPausedSeconds = nextTotal;
        _isWorkoutPaused = pause;
        final startedAt = _activeStartedAt;
        if (startedAt != null) {
          final currentPause = pause ? now.difference(now).inSeconds : 0;
          _elapsedSeconds = (now.difference(startedAt).inSeconds - nextTotal - currentPause).clamp(0, 1 << 30).toInt();
        }
        _activeWorkout = {...?_activeWorkout, 'pausedAt': pause ? Timestamp.fromDate(now) : null, 'totalPausedSeconds': nextTotal};
      });
      _elapsedSecondsNotifier.value = _elapsedSeconds;
      if (_activeWorkout?['gpsTracking'] == true) {
        if (pause) {
          await _gpsSubscription?.cancel();
          _gpsSubscription = null;
          _lastGpsPosition = null;
        } else {
          await _startGpsLocationStream();
        }
      }
    } catch (_) {
      _showMessage('Could not update workout pause state. Please try again.');
    }
  }

  Future<void> _openGuidedWorkout() async {
    final id = _activeWorkoutId;
    final data = _activeWorkout;
    if (id == null || data == null) return;
    final ids = (data['plannedExerciseIds'] as List<dynamic>? ?? const []).cast<String>();
    final exercises = ids
        .map((exerciseId) => _exerciseLibrary.where((item) => item.id == exerciseId).firstOrNull)
        .whereType<_Exercise>()
        .toList();
    if (exercises.isEmpty) {
      _showMessage('This session has no planned exercises. Start a program or custom workout to use guided training.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _GuidedWorkoutScreen(
        exercises: exercises,
        session: _workouts.doc(id),
        initialIndex: (data['currentExerciseIndex'] as num?)?.toInt() ?? 0,
        initialLogs: (data['exerciseLogs'] as List<dynamic>? ?? const [])
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList(),
        isPaused: _isWorkoutPaused,
        onPauseChanged: _setWorkoutPaused,
      ),
    ));
    if (!mounted) return;
    final refreshed = await _workouts.doc(id).get();
    if (refreshed.exists && mounted) setState(() => _activeWorkout = refreshed.data());
  }

  Widget _buildActiveWorkoutCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = (_activeWorkout?['type'] as String?) ?? 'Workout';
    final displayName = (_activeWorkout?['planName'] as String?) ?? type;
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
                Expanded(child: Text('$displayName in progress', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.bold,
                ))),
                const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: ValueListenableBuilder<int>(
                valueListenable: _elapsedSecondsNotifier,
                builder: (context, elapsedSeconds, child) {
                  return Text(
                    _formatDuration(elapsedSeconds),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
            ),
            if (_activeWorkout?['gpsTracking'] == true) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, color: colors.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text(_formatGpsDistance(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: colors.onSecondaryContainer, fontWeight: FontWeight.bold)),
                ],
              ),
              Center(child: Text(_isWorkoutPaused ? 'GPS paused' : (_currentGpsPosition == null ? 'Acquiring GPS signal…' : 'GPS tracking active'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSecondaryContainer))),
              Center(child: Text('Elevation gain  ${_gpsElevationGainMeters.toStringAsFixed(0)} m', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSecondaryContainer))),
              if (_gpsStatusMessage != null) Center(child: Text(_gpsStatusMessage!, style: TextStyle(color: colors.error, fontSize: 12))),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 230,
                  child: _currentGpsPosition == null
                      ? Container(
                          color: colors.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_searching, size: 30),
                              const SizedBox(height: 8),
                              Text(_isWorkoutPaused ? 'GPS tracking is paused' : 'Waiting for GPS location…'),
                            ],
                          ),
                        )
                      : _LiveGpsRouteMap(
                          points: _gpsRoutePoints,
                          currentPosition: _currentGpsPosition!,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<int>(
                valueListenable: _elapsedSecondsNotifier,
                builder: (context, elapsed, child) {
                  final distanceKm = _gpsDistanceMeters / 1000;
                  final isCycling = (_activeWorkout?['activityMode'] as String? ?? '').toLowerCase() == 'cycling';
                  String metricValue;
                  String metricLabel;
                  if (distanceKm < 0.05 || elapsed <= 0) {
                    metricValue = '--';
                    metricLabel = isCycling ? 'Avg speed' : 'Avg pace';
                  } else if (isCycling) {
                    final speed = distanceKm / (elapsed / 3600);
                    metricValue = '${speed.toStringAsFixed(1)} km/h';
                    metricLabel = 'Avg speed';
                  } else {
                    final paceSeconds = (elapsed / distanceKm).round();
                    metricValue = '${paceSeconds ~/ 60}:${(paceSeconds % 60).toString().padLeft(2, '0')} /km';
                    metricLabel = 'Avg pace';
                  }
                  return Row(
                    children: [
                      Expanded(child: _summaryCard(context, Icons.timer_outlined, 'Elapsed', _formatDuration(elapsed))),
                      const SizedBox(width: 8),
                      Expanded(child: _summaryCard(context, isCycling ? Icons.speed : Icons.av_timer, metricLabel, metricValue)),
                    ],
                  );
                },
              ),
            ],
            if (_activeWorkout?['gpsTracking'] == true) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isFinishing ? null : () => _setWorkoutPaused(!_isWorkoutPaused),
                  icon: Icon(_isWorkoutPaused ? Icons.play_arrow : Icons.pause),
                  label: Text(_isWorkoutPaused ? 'Resume GPS activity' : 'Pause GPS activity'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if ((_activeWorkout?['plannedExerciseIds'] as List<dynamic>?)?.isNotEmpty ?? false) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openGuidedWorkout,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Continue guided workout'),
                ),
              ),
              const SizedBox(height: 10),
            ],
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


  Widget _buildPersonalTrainingSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _fitnessProfile.snapshots(),
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data?.data() ?? <String, dynamic>{};
        final workoutGoal = (profile['weeklyWorkoutGoal'] as num?)?.toInt() ?? 3;
        final minuteGoal = (profile['weeklyMinutesGoal'] as num?)?.toInt() ?? 150;
        final stepGoal = (profile['dailyStepsGoal'] as num?)?.toInt() ?? 10000;
        final days = (profile['trainingDays'] as List<dynamic>?)
                ?.map((value) => value.toString()).toSet() ??
            <String>{'Mon', 'Wed', 'Fri'};
        final focus = profile['trainingFocus'] as String? ?? 'Strength';
        final today = _weekdays[DateTime.now().weekday - 1];
        final isTrainingDay = days.contains(today);
        final weeklyQuery = _workouts
            .where('startedAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(_weekStart(DateTime.now())))
            .orderBy('startedAt', descending: true)
            .limit(100);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: weeklyQuery.snapshots(),
          builder: (context, workoutSnapshot) {
            final completed = (workoutSnapshot.data?.docs ?? [])
                .where((doc) => doc.data()['status'] == 'completed')
                .toList();
            final sessions = completed.length;
            final minutes = completed.fold<int>(
              0,
              (total, doc) => total +
                  (((doc.data()['durationSeconds'] as num?)?.toInt() ?? 0) ~/ 60),
            );
            final sessionProgress =
                (sessions / workoutGoal).clamp(0.0, 1.0).toDouble();
            final minuteProgress =
                (minutes / minuteGoal).clamp(0.0, 1.0).toDouble();
            final stepsProgress = _todaySteps == null
                ? null
                : (_todaySteps! / stepGoal).clamp(0.0, 1.0).toDouble();
            final suggestedPlan = _trainingPlans
                .where((plan) => plan.level == _selectedTrainingLevel && plan.category == focus)
                .firstOrNull;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Personal training',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    TextButton.icon(
                      onPressed: () => _editFitnessProfile(profile),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Edit goals'),
                    ),
                  ],
                ),
                Text('Your targets, weekly plan, and training recommendations.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Weekly progress',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            Text('$sessions / $workoutGoal workouts'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: sessionProgress),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 18),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Active minutes')),
                            Text('$minutes / $minuteGoal min'),
                          ],
                        ),
                        const SizedBox(height: 7),
                        LinearProgressIndicator(value: minuteProgress),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.directions_walk, size: 18),
                            const SizedBox(width: 8),
                            const Expanded(child: Text('Today’s steps')),
                            Text(_todaySteps == null
                                ? 'Health Connect not connected'
                                : '$_todaySteps / $stepGoal'),
                          ],
                        ),
                        if (stepsProgress != null) ...[
                          const SizedBox(height: 7),
                          LinearProgressIndicator(value: stepsProgress),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Weekly schedule',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            TextButton(
                              onPressed: () => _editFitnessProfile(profile),
                              child: const Text('Edit'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _weekdays.map((day) {
                            final selected = days.contains(day);
                            return Chip(
                              avatar: Icon(selected ? Icons.fitness_center : Icons.remove, size: 15),
                              label: Text(day),
                              backgroundColor: selected ? colors.primaryContainer : colors.surface,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 6),
                        Text('Focus: $focus · Level: $_selectedTrainingLevel',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 0,
                  color: colors.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: sessions >= workoutGoal
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weekly workout goal reached',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 5),
                              const Text('You have met your workout target. Prioritize recovery or gentle movement.'),
                            ],
                          )
                        : isTrainingDay && suggestedPlan != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.auto_awesome),
                                      const SizedBox(width: 8),
                                      Text('Today’s recommendation',
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(suggestedPlan.name,
                                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                  Text('${suggestedPlan.durationMinutes} min · ${suggestedPlan.category}'),
                                  const SizedBox(height: 10),
                                  FilledButton.tonal(
                                    onPressed: () => _showPlanDetails(suggestedPlan),
                                    child: const Text('View recommended workout'),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isTrainingDay ? 'Keep your training consistent' : 'Recovery day',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 5),
                                  Text(isTrainingDay
                                      ? 'Choose a suitable session from your training programs when you are ready.'
                                      : 'Today is not a scheduled training day. Rest or choose gentle mobility if it feels good.'),
                                ],
                              ),
                  ),
                ),
                if (profileSnapshot.hasError || workoutSnapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Personal training data could not be loaded. Check your connection and Firestore rules.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGpsRouteHistorySection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final routeQuery = _workouts
        .orderBy('startedAt', descending: true)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: routeQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('GPS route history could not be loaded: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          ));
        }

        final sessions = (snapshot.data?.docs ?? []).map((doc) => doc.data()).where((data) {
          return data['gpsTracking'] == true && data['status'] == 'completed';
        }).toList();
        final filtered = sessions.where((data) {
          if (_gpsHistoryFilter == 'All') return true;
          return (data['activityMode'] as String? ?? data['type'] as String? ?? '') == _gpsHistoryFilter;
        }).toList();

        double distanceOf(Map<String, dynamic> data) {
          final km = (data['distanceKm'] as num?)?.toDouble();
          if (km != null && km > 0) return km;
          return ((data['gpsDistanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
        }

        int durationOf(Map<String, dynamic> data) =>
            (data['durationSeconds'] as num?)?.toInt() ?? 0;


        final walking = sessions.where((d) => (d['activityMode'] as String? ?? '') == 'Walking').toList();
        final running = sessions.where((d) => (d['activityMode'] as String? ?? '') == 'Running').toList();
        final cycling = sessions.where((d) => (d['activityMode'] as String? ?? '') == 'Cycling').toList();
        double bestDistance(List<Map<String, dynamic>> items) => items.fold<double>(0, (best, d) => distanceOf(d) > best ? distanceOf(d) : best);
        double bestRunPace = double.infinity;
        for (final data in running) {
          final km = distanceOf(data);
          final seconds = durationOf(data);
          if (km >= 0.1 && seconds > 0) {
            final pace = seconds / km;
            if (pace < bestRunPace) bestRunPace = pace;
          }
        }
        double bestCycleSpeed = 0;
        for (final data in cycling) {
          final km = distanceOf(data);
          final seconds = durationOf(data);
          if (km > 0 && seconds > 0) {
            final speed = km / (seconds / 3600);
            if (speed > bestCycleSpeed) bestCycleSpeed = speed;
          }
        }

        String paceLabel(double secondsPerKm) {
          if (!secondsPerKm.isFinite) return '—';
          final total = secondsPerKm.round();
          return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')} /km';
        }

        String dateLabel(Map<String, dynamic> data) {
          final raw = data['startedAt'];
          final date = raw is Timestamp ? raw.toDate() : raw is DateTime ? raw : null;
          return date == null ? 'Date unavailable' : DateFormat('EEE, MMM d · h:mm a').format(date);
        }

        List<Map<String, dynamic>> pointsOf(Map<String, dynamic> data) {
          final raw = data['routePoints'];
          if (raw is! List) return [];
          return raw.whereType<Map>().map((point) => Map<String, dynamic>.from(point)).where((point) {
            return point['latitude'] is num && point['longitude'] is num;
          }).toList();
        }

        List<Map<String, dynamic>> splitsOf(Map<String, dynamic> data) {
          final raw = data['gpsSplits'];
          if (raw is List) {
            return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
          }
          return _calculateGpsSplits(pointsOf(data));
        }

        double elevationGainOf(Map<String, dynamic> data, List<Map<String, dynamic>> points) {
          final saved = (data['gpsElevationGainMeters'] as num?)?.toDouble();
          if (saved != null) return saved;
          var gain = 0.0;
          double? previousAltitude;
          for (final point in points) {
            final altitude = (point['altitude'] as num?)?.toDouble();
            if (altitude == null) continue;
            if (previousAltitude != null) {
              final change = altitude - previousAltitude;
              if (change > 1.5 && change < 30) gain += change;
            }
            previousAltitude = altitude;
          }
          return gain;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GPS activity & routes', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Saved walks, runs, and rides', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (sessions.isNotEmpty) ...[
              Text('GPS personal bests', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.85,
                children: [
                  _summaryCard(context, Icons.route, 'Longest walk', bestDistance(walking) > 0 ? '${bestDistance(walking).toStringAsFixed(2)} km' : '—'),
                  _summaryCard(context, Icons.directions_run, 'Longest run', bestDistance(running) > 0 ? '${bestDistance(running).toStringAsFixed(2)} km' : '—'),
                  _summaryCard(context, Icons.speed, 'Best run pace', paceLabel(bestRunPace)),
                  _summaryCard(context, Icons.directions_bike, 'Top cycling speed', bestCycleSpeed > 0 ? '${bestCycleSpeed.toStringAsFixed(1)} km/h' : '—'),
                ],
              ),
              const SizedBox(height: 16),
            ],
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'All', label: Text('All')),
                ButtonSegment(value: 'Walking', label: Text('Walk')),
                ButtonSegment(value: 'Running', label: Text('Run')),
                ButtonSegment(value: 'Cycling', label: Text('Cycle')),
              ],
              selected: {_gpsHistoryFilter},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _gpsHistoryFilter = selection.first),
              expandedInsets: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Center(
                    child: Text(sessions.isEmpty
                        ? 'Complete a GPS walk, run, or ride and your route will appear here.'
                        : 'No ${_gpsHistoryFilter.toLowerCase()} activities yet.'),
                  ),
                ),
              )
            else
              ...filtered.map((data) {
                final activity = data['activityMode'] as String? ?? data['type'] as String? ?? 'GPS activity';
                final km = distanceOf(data);
                final seconds = durationOf(data);
                final points = pointsOf(data);
                final splits = splitsOf(data);
                final elevationGain = elevationGainOf(data, points);
                final pace = km > 0 && seconds > 0 ? seconds / km : null;
                final speed = km > 0 && seconds > 0 ? km / (seconds / 3600) : null;
                final icon = activity == 'Running'
                    ? Icons.directions_run
                    : activity == 'Cycling'
                        ? Icons.directions_bike
                        : Icons.directions_walk;
                return Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  margin: const EdgeInsets.only(bottom: 8),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      child: Icon(icon, color: colors.onPrimaryContainer),
                    ),
                    title: Text(activity, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${dateLabel(data)}\n${km.toStringAsFixed(2)} km · ${_formatDuration(seconds)}'),
                    isThreeLine: true,
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                    children: [
                      if (points.length >= 2) ...[
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _GpsRouteMap(
                            points: points,
                            routeColor: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Street map · drag to pan and pinch to zoom', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Route points were not saved for this activity.'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(child: _summaryCard(context, Icons.route, 'Distance', '${km.toStringAsFixed(2)} km')),
                          const SizedBox(width: 8),
                          Expanded(child: _summaryCard(context, Icons.timer_outlined, 'Duration', _formatDuration(seconds))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _summaryCard(context, Icons.terrain, 'Elevation gain', '${elevationGain.toStringAsFixed(0)} m')),
                          const SizedBox(width: 8),
                          Expanded(child: _summaryCard(context, Icons.place_outlined, 'GPS points', '${points.length}')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (activity == 'Running' && pace != null)
                            Expanded(child: _summaryCard(context, Icons.speed, 'Average pace', paceLabel(pace)))
                          else if (activity == 'Cycling' && speed != null)
                            Expanded(child: _summaryCard(context, Icons.speed, 'Average speed', '${speed.toStringAsFixed(1)} km/h'))
                          else
                            Expanded(child: _summaryCard(context, Icons.timer, 'Average pace', pace == null ? '—' : paceLabel(pace))),
                        ],
                      ),
                      if (splits.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Automatic kilometer splits', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 6),
                        ...splits.map((split) {
                          final splitNumber = (split['split'] as num?)?.toInt() ?? 0;
                          final splitDistance = (split['distanceKm'] as num?)?.toDouble() ?? 1.0;
                          final splitSeconds = (split['durationSeconds'] as num?)?.toInt() ?? 0;
                          final paceText = splitDistance > 0
                              ? paceLabel(splitSeconds / splitDistance)
                              : '—';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(child: Text(splitDistance < 0.999 ? 'Final partial split' : 'Split $splitNumber')),
                                Text('${splitDistance.toStringAsFixed(2)} km'),
                                const SizedBox(width: 16),
                                Text(paceText, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                );
              }),
            if (sessions.length >= 100)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Showing your 100 most recent workout sessions.', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGpsGoalsAndStatsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final since = DateTime.now().subtract(const Duration(days: 7));
    final weeklyQuery = _workouts
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('startedAt', descending: true)
        .limit(100);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _fitnessProfile.snapshots(),
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data?.data() ?? <String, dynamic>{};
        final distanceGoal = (profile['gpsWeeklyDistanceGoalKm'] as num?)?.toDouble() ?? 15.0;
        final sessionGoal = (profile['gpsWeeklySessionGoal'] as num?)?.toInt() ?? 3;
        final targetActivity = profile['gpsGoalActivity'] as String? ?? 'All activities';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: weeklyQuery.snapshots(),
          builder: (context, workoutSnapshot) {
            if (workoutSnapshot.hasError) {
              return Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('GPS statistics could not be loaded: ${workoutSnapshot.error}'),
              ));
            }
            final sessions = (workoutSnapshot.data?.docs ?? []).map((doc) => doc.data()).where((data) {
              if (data['gpsTracking'] != true || data['status'] != 'completed') return false;
              if (targetActivity == 'All activities') return true;
              return (data['activityMode'] as String? ?? '') == targetActivity;
            }).toList();

            double distanceOf(Map<String, dynamic> data) {
              final stored = (data['distanceKm'] as num?)?.toDouble();
              if (stored != null && stored > 0) return stored;
              return ((data['gpsDistanceMeters'] as num?)?.toDouble() ?? 0) / 1000;
            }
            int durationOf(Map<String, dynamic> data) =>
                (data['durationSeconds'] as num?)?.toInt() ?? 0;

            final totalDistance = sessions.fold<double>(0, (sum, data) => sum + distanceOf(data));
            final totalSeconds = sessions.fold<int>(0, (sum, data) => sum + durationOf(data));
            final distanceProgress = (totalDistance / distanceGoal).clamp(0.0, 1.0).toDouble();
            final sessionProgress = (sessions.length / sessionGoal).clamp(0.0, 1.0).toDouble();
            final avgPace = totalDistance > 0 ? totalSeconds / totalDistance : 0.0;
            final avgSpeed = totalSeconds > 0 ? totalDistance / (totalSeconds / 3600) : 0.0;
            String paceText(double value) {
              if (value <= 0 || !value.isFinite) return '—';
              final rounded = value.round();
              return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')} /km';
            }
            final activityLabel = targetActivity == 'All activities' ? 'All GPS activities' : targetActivity;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('GPS goals & weekly stats', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () => _editGpsGoals(profile),
                      icon: const Icon(Icons.tune, size: 17),
                      label: const Text('Edit goals'),
                    ),
                  ],
                ),
                Text('Rolling 7-day progress · $activityLabel', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 10),
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text('Distance goal', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                          Text('${totalDistance.toStringAsFixed(1)} / ${distanceGoal.toStringAsFixed(0)} km', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(value: distanceProgress, minHeight: 9),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(child: Text('Activity goal', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                          Text('${sessions.length} / $sessionGoal sessions', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(value: sessionProgress, minHeight: 9),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.85,
                  children: [
                    _summaryCard(context, Icons.route_outlined, 'Distance', '${totalDistance.toStringAsFixed(2)} km'),
                    _summaryCard(context, Icons.flag_outlined, 'Activities', '${sessions.length}'),
                    _summaryCard(context, Icons.timer_outlined, 'Active time', _formatDuration(totalSeconds)),
                    _summaryCard(
                      context,
                      Icons.speed,
                      targetActivity == 'Cycling' ? 'Average speed' : 'Average pace',
                      targetActivity == 'Cycling'
                          ? (avgSpeed > 0 ? '${avgSpeed.toStringAsFixed(1)} km/h' : '—')
                          : (targetActivity == 'Running' || targetActivity == 'Walking' ? paceText(avgPace) : (avgSpeed > 0 ? '${avgSpeed.toStringAsFixed(1)} km/h' : '—')),
                    ),
                  ],
                ),
                if (workoutSnapshot.connectionState == ConnectionState.waiting && !workoutSnapshot.hasData)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Loading recent GPS activity…', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editGpsGoals(Map<String, dynamic> current) async {
    double distanceGoal = (current['gpsWeeklyDistanceGoalKm'] as num?)?.toDouble() ?? 15.0;
    int sessionGoal = (current['gpsWeeklySessionGoal'] as num?)?.toInt() ?? 3;
    String targetActivity = current['gpsGoalActivity'] as String? ?? 'All activities';
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('GPS activity goals'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Track progress for', style: Theme.of(context).textTheme.labelLarge),
                DropdownButtonFormField<String>(
                  value: targetActivity,
                  items: const ['All activities', 'Walking', 'Running', 'Cycling']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) { if (value != null) setDialogState(() => targetActivity = value); },
                ),
                const SizedBox(height: 14),
                Text('Weekly distance target', style: Theme.of(context).textTheme.labelLarge),
                DropdownButtonFormField<double>(
                  value: distanceGoal,
                  items: const [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0]
                      .map((value) => DropdownMenuItem(value: value, child: Text('${value.toStringAsFixed(0)} km')))
                      .toList(),
                  onChanged: (value) { if (value != null) setDialogState(() => distanceGoal = value); },
                ),
                const SizedBox(height: 14),
                Text('Activities per 7 days', style: Theme.of(context).textTheme.labelLarge),
                DropdownButtonFormField<int>(
                  value: sessionGoal,
                  items: List.generate(7, (index) => index + 1)
                      .map((value) => DropdownMenuItem(value: value, child: Text('$value activities')))
                      .toList(),
                  onChanged: (value) { if (value != null) setDialogState(() => sessionGoal = value); },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save goals')),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    try {
      await _fitnessProfile.set({
        'gpsWeeklyDistanceGoalKm': distanceGoal,
        'gpsWeeklySessionGoal': sessionGoal,
        'gpsGoalActivity': targetActivity,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) _showMessage('GPS activity goals saved.');
    } catch (_) {
      if (mounted) _showMessage('GPS goals could not be saved. Check Firestore rules and connection.');
    }
  }

  Widget _buildPersonalRecordsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _fitnessProfile.snapshots(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data() ?? <String, dynamic>{};
        final rawRecords = profile['personalRecords'];
        final records = rawRecords is Map
            ? Map<String, dynamic>.from(rawRecords)
            : <String, dynamic>{};
        final entries = records.entries.toList();
        entries.sort((a, b) {
          final aData = a.value is Map ? Map<String, dynamic>.from(a.value as Map) : <String, dynamic>{};
          final bData = b.value is Map ? Map<String, dynamic>.from(b.value as Map) : <String, dynamic>{};
          final aDate = aData['updatedAt'] is Timestamp
              ? (aData['updatedAt'] as Timestamp).toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = bData['updatedAt'] is Timestamp
              ? (bData['updatedAt'] as Timestamp).toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

        String recordValue(Map<String, dynamic> record) {
          final duration = (record['bestDurationSeconds'] as num?)?.toInt();
          if (duration != null) return '${duration}s';
          final weight = (record['bestWeightKg'] as num?)?.toDouble();
          final reps = (record['bestReps'] as num?)?.toInt();
          if (weight != null && reps != null) {
            final weightLabel = weight == weight.roundToDouble()
                ? weight.toStringAsFixed(0)
                : weight.toStringAsFixed(1);
            return '${weightLabel} kg × $reps';
          }
          return 'Record saved';
        }

        final recordCount = entries.length;
        final milestone = recordCount >= 10
            ? 'Record collector · 10+ personal records'
            : recordCount >= 5
                ? 'Building momentum · 5+ personal records'
                : recordCount >= 1
                    ? 'First record earned · Keep progressing'
                    : 'Your first record is waiting';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress & personal records',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events_outlined, color: colors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('$recordCount personal ${recordCount == 1 ? 'record' : 'records'}',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(milestone, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    if (recordCount == 0) ...[
                      const SizedBox(height: 12),
                      const Text('Complete sets in a guided workout to start tracking your best performances.'),
                    ] else ...[
                      const SizedBox(height: 12),
                      ...entries.take(6).map((entry) {
                        final record = entry.value is Map
                            ? Map<String, dynamic>.from(entry.value as Map)
                            : <String, dynamic>{};
                        final name = record['exerciseName'] as String? ?? entry.key;
                        final updatedAt = record['updatedAt'] is Timestamp
                            ? (record['updatedAt'] as Timestamp).toDate()
                            : null;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: colors.primaryContainer,
                            child: Icon(Icons.trending_up, color: colors.onPrimaryContainer, size: 19),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(updatedAt == null ? 'Personal best' : 'Updated ${DateFormat('MMM d').format(updatedAt)}'),
                          trailing: Text(recordValue(record), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                        );
                      }),
                      if (recordCount > 6)
                        Text('+ ${recordCount - 6} more records', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                    if (snapshot.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Personal records could not be loaded.', style: theme.textTheme.bodySmall?.copyWith(color: colors.error)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editFitnessProfile(Map<String, dynamic> current) async {
    int workoutGoal = (current['weeklyWorkoutGoal'] as num?)?.toInt() ?? 3;
    int minuteGoal = (current['weeklyMinutesGoal'] as num?)?.toInt() ?? 150;
    int stepGoal = (current['dailyStepsGoal'] as num?)?.toInt() ?? 10000;
    String focus = current['trainingFocus'] as String? ?? 'Strength';
    final days = (current['trainingDays'] as List<dynamic>?)
            ?.map((value) => value.toString()).toSet() ??
        <String>{'Mon', 'Wed', 'Fri'};

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Personal training goals'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workouts per week', style: Theme.of(context).textTheme.labelLarge),
                  DropdownButtonFormField<int>(
                    value: workoutGoal,
                    items: List.generate(7, (index) => index + 1)
                        .map((value) => DropdownMenuItem(value: value, child: Text('$value workouts')))
                        .toList(),
                    onChanged: (value) { if (value != null) setDialogState(() => workoutGoal = value); },
                  ),
                  const SizedBox(height: 12),
                  Text('Active minutes per week', style: Theme.of(context).textTheme.labelLarge),
                  DropdownButtonFormField<int>(
                    value: minuteGoal,
                    items: const [60, 90, 120, 150, 180, 210, 240, 300]
                        .map((value) => DropdownMenuItem(value: value, child: Text('$value minutes')))
                        .toList(),
                    onChanged: (value) { if (value != null) setDialogState(() => minuteGoal = value); },
                  ),
                  const SizedBox(height: 12),
                  Text('Daily step target', style: Theme.of(context).textTheme.labelLarge),
                  DropdownButtonFormField<int>(
                    value: stepGoal,
                    items: const [4000, 5000, 6000, 7000, 8000, 9000, 10000, 11000, 12000, 15000]
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(NumberFormat('#,###').format(value)),
                            ))
                        .toList(),
                    onChanged: (value) { if (value != null) setDialogState(() => stepGoal = value); },
                  ),
                  const SizedBox(height: 12),
                  Text('Training focus', style: Theme.of(context).textTheme.labelLarge),
                  DropdownButtonFormField<String>(
                    value: focus,
                    items: const ['Strength', 'Cardio', 'Mobility', 'Conditioning']
                        .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) { if (value != null) setDialogState(() => focus = value); },
                  ),
                  const SizedBox(height: 16),
                  Text('Training days', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _weekdays.map((day) => FilterChip(
                      label: Text(day),
                      selected: days.contains(day),
                      onSelected: (selected) => setDialogState(() {
                        if (selected) { days.add(day); } else { days.remove(day); }
                      }),
                    )).toList(),
                  ),
                  if (days.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Choose at least one training day.',
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: days.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('Save goals'),
            ),
          ],
        ),
      ),
    );

    if (save != true || !mounted) return;
    try {
      await _fitnessProfile.set({
        'weeklyWorkoutGoal': workoutGoal,
        'weeklyMinutesGoal': minuteGoal,
        'dailyStepsGoal': stepGoal,
        'trainingFocus': focus,
        'trainingDays': _weekdays.where(days.contains).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) _showMessage('Personal training goals saved.');
    } catch (_) {
      if (mounted) _showMessage('Goals could not be saved. Check Firestore rules and connection.');
    }
  }

  Widget _buildTrainingInsightsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final currentStart = now.subtract(const Duration(days: 7));
    final previousStart = now.subtract(const Duration(days: 14));

    final recentSessions = _workouts
        .where(
          'startedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(previousStart),
        )
        .orderBy('startedAt', descending: true)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: recentSessions.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Training insights are temporarily unavailable.'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final sessions = (snapshot.data?.docs ?? [])
            .map((doc) => doc.data())
            .where((data) => data['status'] == 'completed')
            .toList();

        DateTime? sessionDate(Map<String, dynamic> data) {
          final value = data['startedAt'];
          if (value is Timestamp) return value.toDate();
          if (value is DateTime) return value;
          return null;
        }

        final current = sessions.where((data) {
          final date = sessionDate(data);
          return date != null && !date.isBefore(currentStart) && !date.isAfter(now);
        }).toList();
        final previous = sessions.where((data) {
          final date = sessionDate(data);
          return date != null && !date.isBefore(previousStart) && date.isBefore(currentStart);
        }).toList();

        int minutes(List<Map<String, dynamic>> items) => items.fold<int>(
              0,
              (total, data) => total +
                  (((data['durationSeconds'] as num?)?.toInt() ?? 0) ~/ 60),
            );
        double distance(List<Map<String, dynamic>> items) => items.fold<double>(
              0,
              (total, data) => total +
                  ((data['distanceKm'] as num?)?.toDouble() ?? 0),
            );

        final currentMinutes = minutes(current);
        final previousMinutes = minutes(previous);
        final currentDistance = distance(current);
        final previousDistance = distance(previous);
        final typeCounts = <String, int>{};
        for (final item in current) {
          final type = (item['type'] as String?)?.trim();
          if (type != null && type.isNotEmpty) {
            typeCounts[type] = (typeCounts[type] ?? 0) + 1;
          }
        }
        final topTypes = typeCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        String comparison(int value, int prior) {
          if (value == prior) return 'No change';
          final difference = value - prior;
          final percent = prior == 0
              ? null
              : (difference.abs() / prior * 100).round();
          final amount = percent == null ? '$difference' : '$percent%';
          return difference > 0 ? '↑ $amount' : '↓ $amount';
        }

        final sessionChange = comparison(current.length, previous.length);
        final minuteChange = comparison(currentMinutes, previousMinutes);
        final distanceChange = previousDistance <= 0
            ? (currentDistance > 0 ? 'New activity' : 'No change')
            : currentDistance == previousDistance
                ? 'No change'
                : '${currentDistance > previousDistance ? '↑' : '↓'} ${( ((currentDistance - previousDistance).abs() / previousDistance) * 100).round()}%';
        final hasData = current.isNotEmpty || previous.isNotEmpty;
        final insight = !hasData
            ? 'Complete a workout to start building your training insights.'
            : current.length > previous.length
                ? 'You completed more workouts than in the previous 7 days. Keep building that consistency.'
                : currentMinutes > previousMinutes
                    ? 'Your total training time is up compared with the previous 7 days.'
                    : current.isEmpty
                        ? 'No completed workouts in the last 7 days. Your previous activity is still available in workout history.'
                        : 'Use this week as a fresh baseline and keep your training consistent.';

        Widget metric(String label, String value, String change, IconData icon) {
          return Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 19, color: colors.primary),
                const SizedBox(height: 7),
                Text(value, style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
                Text(label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 3),
                Text(change, style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                )),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Training insights',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Last 7 days compared with the 7 days before',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        metric('Workouts', '${current.length}', sessionChange, Icons.fitness_center),
                        const SizedBox(width: 8),
                        metric('Training time', '${currentMinutes}m', minuteChange, Icons.timer_outlined),
                        const SizedBox(width: 8),
                        metric('Distance', '${currentDistance.toStringAsFixed(1)} km',
                            distanceChange, Icons.route_outlined),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(insight, style: theme.textTheme.bodyMedium),
                    if (topTypes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Workout mix', style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: topTypes.map((entry) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${entry.key} · ${entry.value}'),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPerformanceTrendsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final query = _workouts
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('startedAt', descending: true)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Performance trends are temporarily unavailable.'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Each entry represents one completed exercise in one completed
        // workout. Only compare like-for-like exercises across sessions.
        final byExercise = <String, List<Map<String, dynamic>>>{};
        for (final doc in snapshot.data?.docs ?? []) {
          final session = doc.data();
          if (session['status'] != 'completed') continue;
          final started = session['startedAt'];
          final date = started is Timestamp
              ? started.toDate()
              : started is DateTime
                  ? started
                  : null;
          if (date == null) continue;
          final rawLogs = session['exerciseLogs'];
          if (rawLogs is! List) continue;

          for (final rawLog in rawLogs) {
            if (rawLog is! Map) continue;
            final log = Map<String, dynamic>.from(rawLog);
            if (log['completed'] != true) continue;
            final exerciseId = log['exerciseId'] as String?;
            if (exerciseId == null || exerciseId.isEmpty) continue;
            final rawSets = log['sets'];
            if (rawSets is! List) continue;
            final sets = rawSets
                .whereType<Map>()
                .map((set) => Map<String, dynamic>.from(set))
                .toList();
            if (sets.isEmpty) continue;

            final isTimed = sets.any((set) => set['durationSeconds'] is num);
            double bestMetric = 0;
            String valueLabel = '';
            if (isTimed) {
              for (final set in sets) {
                final seconds = (set['durationSeconds'] as num?)?.toInt() ?? 0;
                if (seconds > bestMetric) {
                  bestMetric = seconds.toDouble();
                  valueLabel = '$seconds sec';
                }
              }
            } else {
              for (final set in sets) {
                final reps = (set['reps'] as num?)?.toInt();
                final weight = (set['weightKg'] as num?)?.toDouble();
                if (reps == null || weight == null || reps < 0 || weight < 0) continue;
                final metric = weight * reps;
                if (metric > bestMetric) {
                  bestMetric = metric;
                  final weightText = weight == weight.roundToDouble()
                      ? weight.toStringAsFixed(0)
                      : weight.toStringAsFixed(1);
                  valueLabel = '$weightText kg × $reps';
                }
              }
            }
            if (bestMetric <= 0 || valueLabel.isEmpty) continue;
            byExercise.putIfAbsent(exerciseId, () => <Map<String, dynamic>>[]).add({
              'date': date,
              'metric': bestMetric,
              'label': valueLabel,
              'timed': isTimed,
            });
          }
        }

        final trends = <Map<String, dynamic>>[];
        for (final entry in byExercise.entries) {
          final entries = entry.value
            ..sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
          if (entries.length < 2) continue;
          final previous = entries[entries.length - 2];
          final latest = entries.last;
          final oldMetric = previous['metric'] as double;
          final newMetric = latest['metric'] as double;
          final change = oldMetric == 0 ? 0.0 : ((newMetric - oldMetric) / oldMetric) * 100;
          final exercise = _exerciseLibrary.where((item) => item.id == entry.key).firstOrNull;
          trends.add({
            'name': exercise?.name ?? entry.key,
            'latestLabel': latest['label'],
            'previousLabel': previous['label'],
            'change': change,
            'date': latest['date'],
            'timed': latest['timed'],
            'sessions': entries.length,
          });
        }
        trends.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
        final displayed = trends.take(5).toList();
        final trackedCount = byExercise.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance trends', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Exercise-by-exercise comparisons from your last 90 days of completed guided workouts.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.insights_outlined, color: colors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('$trackedCount exercises tracked', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Text('90 days', style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (displayed.isEmpty)
                      Text(
                        'Complete the same guided exercise in at least two workouts to see how your performance changes here.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      )
                    else
                      ...displayed.map((trend) {
                        final change = trend['change'] as double;
                        final improved = change > 0.5;
                        final declined = change < -0.5;
                        final color = improved
                            ? colors.primary
                            : declined
                                ? colors.error
                                : colors.onSurfaceVariant;
                        final icon = improved
                            ? Icons.trending_up
                            : declined
                                ? Icons.trending_down
                                : Icons.trending_flat;
                        final changeText = '${change > 0 ? '+' : ''}${change.toStringAsFixed(0)}%';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(trend['name'] as String, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                  Icon(icon, size: 18, color: color),
                                  const SizedBox(width: 3),
                                  Text(changeText, style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Previous: ${trend['previousLabel']}   ·   Latest: ${trend['latestLabel']}',
                                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              Text(
                                '${trend['sessions']} sessions logged · compared with your previous session',
                                style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        );
                      }),
                    const Divider(height: 8),
                    Text(
                      'Strength comparisons use the best set volume (weight × reps); timed exercises use the longest logged set. These are session-to-session comparisons, not medical or form assessments.',
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTrainingCoachOverlay() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final screenHeight = MediaQuery.of(sheetContext).size.height;
        return SizedBox(
          height: screenHeight * 0.78,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: _buildTrainingCoachSection(sheetContext),
          ),
        );
      },
    );
  }

  Widget _buildTrainingCoachSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recentSessions = _workouts
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('startedAt', descending: true)
        .limit(30);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: recentSessions.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Training coach', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Training suggestions are temporarily unavailable.', style: theme.textTheme.bodySmall),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final suggestions = <Map<String, dynamic>>[];
        final latestByExercise = <String, Map<String, dynamic>>{};
        for (final doc in snapshot.data?.docs ?? []) {
          final session = doc.data();
          if (session['status'] != 'completed') continue;
          final logs = session['exerciseLogs'];
          if (logs is! List) continue;
          for (final rawLog in logs) {
            if (rawLog is! Map) continue;
            final log = Map<String, dynamic>.from(rawLog);
            final id = log['exerciseId'] as String?;
            if (id == null || id.isEmpty || latestByExercise.containsKey(id)) continue;
            if (log['completed'] != true) continue;
            final setsRaw = log['sets'];
            final sets = setsRaw is List
                ? setsRaw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
                : <Map<String, dynamic>>[];
            if (sets.isEmpty) continue;
            latestByExercise[id] = {
              'log': log,
              'sets': sets,
            };
          }
        }

        for (final entry in latestByExercise.entries) {
          final exercise = _exerciseLibrary.where((item) => item.id == entry.key).firstOrNull;
          final log = entry.value['log'] as Map<String, dynamic>;
          final sets = entry.value['sets'] as List<Map<String, dynamic>>;
          final isTimed = sets.first.containsKey('durationSeconds');
          final completedSetCount = sets.length;
          String recommendation;
          String rationale;
          IconData icon;

          if (isTimed) {
            final durations = sets
                .map((set) => (set['durationSeconds'] as num?)?.toInt())
                .whereType<int>()
                .where((value) => value > 0)
                .toList();
            final average = durations.isEmpty
                ? 0
                : (durations.reduce((a, b) => a + b) / durations.length).round();
            final shortest = durations.isEmpty ? 0 : durations.reduce((a, b) => a < b ? a : b);
            if (completedSetCount >= 3 && durations.length >= 3) {
              final increment = shortest >= 45 ? 5 : (shortest >= 20 ? 3 : 2);
              recommendation = 'Aim for about ${average + increment} seconds per set next time.';
              rationale = 'Your ${durations.length} logged sets averaged ${average}s, with your shortest at ${shortest}s. A small time increase is a measured next step.';
              icon = Icons.timer_outlined;
            } else {
              recommendation = 'Build toward 3 timed sets of about ${average > 0 ? '$average seconds' : 'a consistent duration'}.';
              rationale = 'You logged $completedSetCount set${completedSetCount == 1 ? '' : 's'} so far. Establish a repeatable baseline before extending the hold or interval.';
              icon = Icons.repeat;
            }
          } else {
            final validSets = sets.where((set) =>
                set['reps'] is num && set['weightKg'] is num).toList();
            final reps = validSets.map((set) => (set['reps'] as num).toInt()).toList();
            final weights = validSets.map((set) => (set['weightKg'] as num).toDouble()).toList();
            final lowestReps = reps.isEmpty ? 0 : reps.reduce((a, b) => a < b ? a : b);
            final highestReps = reps.isEmpty ? 0 : reps.reduce((a, b) => a > b ? a : b);
            final averageReps = reps.isEmpty ? 0 : (reps.reduce((a, b) => a + b) / reps.length).round();
            final load = weights.isEmpty ? 0.0 : weights.last;
            final sameLoad = weights.isNotEmpty && weights.every((value) => (value - load).abs() < 0.001);

            if (completedSetCount >= 3 && reps.length >= 3 && sameLoad && lowestReps >= 12 && load > 0) {
              recommendation = 'Consider the next small weight increment, aiming for 8–10 controlled reps.';
              rationale = 'You completed ${reps.length} sets at ${load.toStringAsFixed(load == load.roundToDouble() ? 0 : 1)} kg, averaging $averageReps reps (minimum $lowestReps).';
              icon = Icons.fitness_center;
            } else if (completedSetCount >= 3 && reps.length >= 3 && lowestReps >= 12 && load == 0) {
              recommendation = 'Try adding 1–2 reps to each set while keeping your form steady.';
              rationale = 'Your bodyweight sets averaged $averageReps reps, and every logged set reached at least $lowestReps.';
              icon = Icons.trending_up;
            } else if (completedSetCount >= 3 && reps.length >= 3 && highestReps - lowestReps <= 2) {
              recommendation = 'Keep the same load and add 1 rep to your lowest-rep set.';
              rationale = 'Your sets were consistent at $lowestReps–$highestReps reps using ${load.toStringAsFixed(load == load.roundToDouble() ? 0 : 1)} kg.';
              icon = Icons.trending_up;
            } else if (reps.isNotEmpty) {
              recommendation = 'Keep ${load.toStringAsFixed(load == load.roundToDouble() ? 0 : 1)} kg and aim to bring every set up to $averageReps reps.';
              rationale = 'Your logged sets ranged from $lowestReps to $highestReps reps. Improve consistency before increasing the load.';
              icon = Icons.repeat;
            } else {
              recommendation = 'Log your reps and weight for each set to unlock a specific progression.';
              rationale = 'There is not enough strength-set detail yet to calculate a useful next step.';
              icon = Icons.edit_note;
            }
          }

          suggestions.add({
            'name': exercise?.name ?? (log['exerciseName'] as String? ?? entry.key),
            'recommendation': recommendation,
            'rationale': rationale,
            'icon': icon,
          });
        }

        final displayed = suggestions.take(4).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Training coach', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(
              'Practical next-session suggestions based on your recent guided workouts.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: displayed.isEmpty
                    ? const Text('Complete a guided workout with logged exercise sets to receive progression suggestions here.')
                    : Column(
                        children: [
                          ...displayed.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: colors.primaryContainer,
                                  child: Icon(item['icon'] as IconData, size: 19, color: colors.onPrimaryContainer),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 3),
                                      Text(item['recommendation'] as String),
                                      const SizedBox(height: 2),
                                      Text(item['rationale'] as String, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )),
                          const Divider(),
                          Text(
                            'These are optional training suggestions, not automatic changes. Increase difficulty only when your form and recovery feel good.',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrainingProgramsSection(BuildContext context) {
    final theme = Theme.of(context);
    final plans = _trainingPlans
        .where((plan) => plan.level == _selectedTrainingLevel)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Training programs', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(
          'Choose a structured program that matches your experience.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Beginner', label: Text('Beginner'), icon: Icon(Icons.directions_walk)),
            ButtonSegment(value: 'Intermediate', label: Text('Intermediate')),
            ButtonSegment(value: 'Advanced', label: Text('Advanced')),
          ],
          selected: {_selectedTrainingLevel},
          onSelectionChanged: (selection) {
            setState(() => _selectedTrainingLevel = selection.first);
          },
          showSelectedIcon: false,
        ),
        const SizedBox(height: 12),
        ...plans.map((plan) => _buildTrainingPlanCard(context, plan)),
      ],
    );
  }

  Widget _buildTrainingPlanCard(BuildContext context, _WorkoutPlan plan) {
    final colors = Theme.of(context).colorScheme;
    final icon = _iconForCategory(plan.category);
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPlanDetails(plan),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: colors.primaryContainer,
                child: Icon(icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(plan.description, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      '${plan.durationMinutes} min  ·  ${plan.exerciseIds.length} exercises  ·  ${plan.category}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Strength':
        return Icons.fitness_center;
      case 'Cardio':
        return Icons.directions_run;
      case 'Mobility':
        return Icons.self_improvement;
      case 'Conditioning':
        return Icons.bolt;
      default:
        return Icons.sports;
    }
  }

  Future<void> _showPlanDetails(_WorkoutPlan plan) async {
    final exercises = plan.exerciseIds
        .map((id) => _exerciseLibrary.where((exercise) => exercise.id == id).firstOrNull)
        .whereType<_Exercise>()
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(plan.name, style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${plan.level} · ${plan.category} · ${plan.durationMinutes} minutes'),
                const SizedBox(height: 10),
                Text(plan.description),
                const SizedBox(height: 18),
                Text('Exercises', style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...exercises.map((exercise) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(_iconForCategory(exercise.category))),
                  title: Text(exercise.name),
                  subtitle: Text('${exercise.category} · ${exercise.equipment}'),
                  trailing: const Icon(Icons.info_outline),
                  onTap: () => _showExerciseDetails(exercise),
                )),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _activeWorkoutId != null || _isStarting
                        ? null
                        : () async {
                            Navigator.pop(sheetContext);
                            await _startWorkout(plan.category, sessionData: {
                              'planId': plan.id,
                              'planName': plan.name,
                              'trainingLevel': plan.level,
                              'plannedExerciseIds': plan.exerciseIds,
                            });
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start this program'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseLibrarySection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Exercise library', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            Text('${_exerciseLibrary.length} exercises', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 5),
        Text('Learn how to perform exercises and explore different training styles.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _showExerciseLibrary,
          icon: const Icon(Icons.search),
          label: const Text('Browse exercise library'),
        ),
      ],
    );
  }

  Future<void> _showExerciseLibrary() async {
    String selectedCategory = 'All';
    final categories = ['All', 'Strength', 'Cardio', 'Mobility', 'Conditioning'];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final exercises = _exerciseLibrary
              .where((exercise) => selectedCategory == 'All' || exercise.category == selectedCategory)
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.82,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exercise library', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((category) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: selectedCategory == category,
                            onSelected: (_) => setSheetState(() => selectedCategory = category),
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(child: Icon(_iconForCategory(exercise.category))),
                            title: Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${exercise.category} · ${exercise.equipment} · ${exercise.level}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showExerciseDetails(exercise),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showExerciseDetails(_Exercise exercise) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(exercise.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                Chip(label: Text(exercise.category)),
                Chip(label: Text(exercise.level)),
                Chip(label: Text(exercise.equipment)),
              ]),
              const SizedBox(height: 8),
              Text(exercise.description),
              const SizedBox(height: 14),
              const Text('How to perform it', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...exercise.instructions.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text('${entry.key + 1}. ${entry.value}'),
              )),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildCustomWorkoutsSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your custom workouts', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'Create custom workout',
              onPressed: _showCustomWorkoutBuilder,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Text('Build a routine from the exercise library.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showCustomWorkoutBuilder,
            icon: const Icon(Icons.add),
            label: const Text('Create a workout'),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _customWorkouts.orderBy('updatedAt', descending: true).limit(10).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Custom workouts could not be loaded. Check your Firestore rules.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Your saved routines will appear here.'),
                ),
              );
            }
            return Column(
              children: docs.map((doc) {
                final data = doc.data();
                final name = data['name'] as String? ?? 'Custom workout';
                final ids = (data['exerciseIds'] as List<dynamic>? ?? []).cast<String>();
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.playlist_add_check)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${data['level'] ?? 'Beginner'} · ${ids.length} exercises'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final selected = ids
                          .map((id) => _exerciseLibrary.where((exercise) => exercise.id == id).firstOrNull)
                          .whereType<_Exercise>()
                          .toList();
                      _showCustomWorkoutDetails(name, data['level'] as String? ?? 'Beginner', selected);
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showCustomWorkoutBuilder() async {
    String name = '';
    String level = _selectedTrainingLevel;
    final selectedIds = <String>{};
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.88,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Build a workout', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(labelText: 'Workout name', hintText: 'e.g. Monday full body', border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: level,
                    decoration: const InputDecoration(labelText: 'Experience level', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Beginner', child: Text('Beginner')),
                      DropdownMenuItem(value: 'Intermediate', child: Text('Intermediate')),
                      DropdownMenuItem(value: 'Advanced', child: Text('Advanced')),
                    ],
                    onChanged: (value) { if (value != null) setSheetState(() => level = value); },
                  ),
                  const SizedBox(height: 12),
                  Text('Select exercises (${selectedIds.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _exerciseLibrary.length,
                      itemBuilder: (context, index) {
                        final exercise = _exerciseLibrary[index];
                        return CheckboxListTile(
                          value: selectedIds.contains(exercise.id),
                          contentPadding: EdgeInsets.zero,
                          title: Text(exercise.name),
                          subtitle: Text('${exercise.category} · ${exercise.level}'),
                          onChanged: (checked) => setSheetState(() {
                            if (checked == true) {
                              selectedIds.add(exercise.id);
                            } else {
                              selectedIds.remove(exercise.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving ? null : () async {
                        final workoutName = name.trim();
                        if (workoutName.isEmpty || selectedIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name and select at least one exercise.')));
                          return;
                        }
                        setSheetState(() => saving = true);
                        try {
                          await _customWorkouts.add({
                            'name': workoutName,
                            'level': level,
                            'exerciseIds': selectedIds.toList(),
                            'createdAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          _showMessage('Custom workout saved.');
                        } catch (error) {
                          if (sheetContext.mounted) {
                            setSheetState(() => saving = false);
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text('Could not save this workout: $error')),
                            );
                          }
                        }
                      },
                      icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving...' : 'Save workout'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomWorkoutDetails(String name, String level, List<_Exercise> exercises) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$level · ${exercises.length} exercises'),
                const SizedBox(height: 12),
                Expanded(
                  child: exercises.isEmpty
                      ? const Center(child: Text('This workout has no available exercises.'))
                      : ListView.builder(
                          itemCount: exercises.length,
                          itemBuilder: (context, index) {
                            final exercise = exercises[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_iconForCategory(exercise.category)),
                              title: Text(exercise.name),
                              subtitle: Text(exercise.category),
                              onTap: () => _showExerciseDetails(exercise),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _activeWorkoutId != null || _isStarting || exercises.isEmpty
                        ? null
                        : () async {
                            Navigator.pop(sheetContext);
                            await _startWorkout('Custom workout', sessionData: {
                              'customWorkoutName': name,
                              'planName': name,
                              'trainingLevel': level,
                              'plannedExerciseIds': exercises.map((exercise) => exercise.id).toList(),
                            });
                          },
                    child: const Text('Start this workout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}


class _Exercise {
  const _Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.equipment,
    required this.level,
    required this.description,
    required this.instructions,
  });

  final String id;
  final String name;
  final String category;
  final String equipment;
  final String level;
  final String description;
  final List<String> instructions;
}

class _WorkoutPlan {
  const _WorkoutPlan({
    required this.id,
    required this.name,
    required this.category,
    required this.level,
    required this.durationMinutes,
    required this.description,
    required this.exerciseIds,
  });

  final String id;
  final String name;
  final String category;
  final String level;
  final int durationMinutes;
  final String description;
  final List<String> exerciseIds;
}

const List<_Exercise> _exerciseLibrary = [
  _Exercise(id: 'bodyweight_squat', name: 'Bodyweight squat', category: 'Strength', equipment: 'None', level: 'Beginner', description: 'A foundational lower-body movement that trains the hips and legs.', instructions: ['Stand with feet about shoulder-width apart.', 'Brace your midsection and sit your hips back and down.', 'Keep your knees tracking in line with your toes.', 'Press through your feet to stand tall.']),
  _Exercise(id: 'wall_push_up', name: 'Wall push-up', category: 'Strength', equipment: 'Wall', level: 'Beginner', description: 'An accessible pushing exercise that builds upper-body strength.', instructions: ['Face a wall and place hands slightly wider than shoulder-width.', 'Step back until your body forms a straight line.', 'Bend your elbows to bring your chest toward the wall.', 'Push back to the starting position.']),
  _Exercise(id: 'incline_push_up', name: 'Incline push-up', category: 'Strength', equipment: 'Stable bench', level: 'Beginner', description: 'A modified push-up with hands elevated on a stable surface.', instructions: ['Place hands on a secure bench or counter.', 'Walk feet back and keep your body straight.', 'Lower your chest toward the surface.', 'Press through your hands to return.']),
  _Exercise(id: 'push_up', name: 'Push-up', category: 'Strength', equipment: 'None', level: 'Intermediate', description: 'A compound upper-body exercise for the chest, shoulders, and arms.', instructions: ['Start in a high plank with hands under or just outside shoulders.', 'Keep your body aligned from head to heels.', 'Lower with control until your chest approaches the floor.', 'Press back up without letting your hips sag.']),
  _Exercise(id: 'reverse_lunge', name: 'Reverse lunge', category: 'Strength', equipment: 'None', level: 'Beginner', description: 'A single-leg movement for the legs, hips, and balance.', instructions: ['Stand tall with feet hip-width apart.', 'Step one foot backward and lower both knees comfortably.', 'Keep your front knee aligned with your foot.', 'Push through the front foot to return and alternate sides.']),
  _Exercise(id: 'glute_bridge', name: 'Glute bridge', category: 'Strength', equipment: 'Mat', level: 'Beginner', description: 'A floor-based exercise that targets the glutes and hip extensors.', instructions: ['Lie on your back with knees bent and feet flat.', 'Brace your abdomen and squeeze your glutes.', 'Lift hips until shoulders, hips, and knees form a line.', 'Lower slowly without arching your lower back.']),
  _Exercise(id: 'plank', name: 'Forearm plank', category: 'Strength', equipment: 'Mat', level: 'Intermediate', description: 'An isometric core exercise focused on maintaining a stable trunk.', instructions: ['Place forearms on the floor with elbows under shoulders.', 'Extend legs and support your body on forearms and toes.', 'Keep ribs down and hips level.', 'Hold while breathing steadily; stop before form breaks.']),
  _Exercise(id: 'dumbbell_row', name: 'Dumbbell row', category: 'Strength', equipment: 'Dumbbells', level: 'Intermediate', description: 'A pulling exercise for the upper back and arms.', instructions: ['Hinge at the hips with a neutral back.', 'Let the dumbbells hang beneath your shoulders.', 'Pull elbows toward your hips without twisting.', 'Lower the weights with control.']),
  _Exercise(id: 'jump_squat', name: 'Jump squat', category: 'Conditioning', equipment: 'None', level: 'Advanced', description: 'An explosive lower-body movement. Use only if jumping is comfortable and appropriate.', instructions: ['Stand with feet about shoulder-width apart.', 'Lower into a controlled squat.', 'Drive through your feet to jump vertically.', 'Land softly with knees tracking over toes and reset.']),
  _Exercise(id: 'brisk_walk', name: 'Brisk walk', category: 'Cardio', equipment: 'Comfortable shoes', level: 'Beginner', description: 'Steady walking at a pace that raises breathing while allowing conversation.', instructions: ['Begin with a comfortable warm-up pace.', 'Increase to a purposeful pace with relaxed shoulders.', 'Swing arms naturally and look ahead.', 'Slow down gradually to cool down.']),
  _Exercise(id: 'march_in_place', name: 'March in place', category: 'Cardio', equipment: 'None', level: 'Beginner', description: 'A low-impact way to raise your heart rate indoors.', instructions: ['Stand tall with feet hip-width apart.', 'Lift one knee at a time in a comfortable rhythm.', 'Swing opposite arms naturally.', 'Keep the movement controlled and breathe steadily.']),
  _Exercise(id: 'jogging', name: 'Easy jog', category: 'Cardio', equipment: 'Running shoes', level: 'Intermediate', description: 'A conversational-pace run for aerobic endurance.', instructions: ['Start with several minutes of brisk walking.', 'Jog at a pace that feels sustainable.', 'Use short, relaxed strides and steady breathing.', 'Finish with an easy walk.']),
  _Exercise(id: 'cycling', name: 'Steady cycling', category: 'Cardio', equipment: 'Bicycle or stationary bike', level: 'Beginner', description: 'Low-impact aerobic training on a bicycle or stationary bike.', instructions: ['Adjust the bike so the riding position feels comfortable.', 'Begin with light resistance.', 'Pedal smoothly at a sustainable effort.', 'Reduce resistance and pedal easily to cool down.']),
  _Exercise(id: 'high_knees', name: 'High knees', category: 'Conditioning', equipment: 'None', level: 'Intermediate', description: 'A rhythmic conditioning drill; use a lower-impact march if needed.', instructions: ['Stand tall with core gently braced.', 'Drive one knee upward while moving the opposite arm.', 'Alternate sides at a controlled rhythm.', 'Keep landings light and reduce speed if form slips.']),
  _Exercise(id: 'mountain_climber', name: 'Mountain climber', category: 'Conditioning', equipment: 'Mat', level: 'Advanced', description: 'A dynamic plank-based conditioning exercise.', instructions: ['Begin in a strong high plank.', 'Bring one knee toward your chest.', 'Switch legs smoothly while keeping shoulders over wrists.', 'Maintain a stable trunk and stop if your lower back sags.']),
  _Exercise(id: 'cat_cow', name: 'Cat-cow', category: 'Mobility', equipment: 'Mat', level: 'Beginner', description: 'A gentle spinal mobility sequence coordinated with breathing.', instructions: ['Start on hands and knees.', 'Exhale and gently round your back.', 'Inhale and move into a comfortable gentle arch.', 'Move slowly without forcing end ranges.']),
  _Exercise(id: 'hip_flexor_stretch', name: 'Half-kneeling hip flexor stretch', category: 'Mobility', equipment: 'Mat', level: 'Beginner', description: 'A gentle stretch for the front of the hip.', instructions: ['Kneel with one foot forward and both knees comfortably bent.', 'Gently tuck your pelvis and brace your abdomen.', 'Shift forward slightly until you feel a mild stretch at the front of the rear hip.', 'Hold while breathing, then switch sides.']),
  _Exercise(id: 'thoracic_rotation', name: 'Open-book rotation', category: 'Mobility', equipment: 'Mat', level: 'Beginner', description: 'A controlled upper-back rotation drill.', instructions: ['Lie on your side with knees bent and arms extended in front.', 'Keep knees stacked as you rotate your top arm and chest open.', 'Move only through a comfortable range.', 'Return slowly and repeat before switching sides.']),
];

const List<_WorkoutPlan> _trainingPlans = [
  _WorkoutPlan(id: 'beginner_full_body', name: 'Full Body Foundations', category: 'Strength', level: 'Beginner', durationMinutes: 25, description: 'Learn fundamental movements with manageable bodyweight exercises.', exerciseIds: ['bodyweight_squat', 'wall_push_up', 'glute_bridge', 'reverse_lunge', 'cat_cow']),
  _WorkoutPlan(id: 'beginner_cardio', name: 'Cardio Starter', category: 'Cardio', level: 'Beginner', durationMinutes: 20, description: 'Build an aerobic routine with low-impact movement.', exerciseIds: ['brisk_walk', 'march_in_place', 'cycling']),
  _WorkoutPlan(id: 'beginner_mobility', name: 'Daily Mobility Reset', category: 'Mobility', level: 'Beginner', durationMinutes: 15, description: 'A gentle routine for comfortable movement and flexibility.', exerciseIds: ['cat_cow', 'hip_flexor_stretch', 'thoracic_rotation']),
  _WorkoutPlan(id: 'beginner_conditioning', name: 'Low-Impact Conditioning', category: 'Conditioning', level: 'Beginner', durationMinutes: 18, description: 'A simple conditioning session with scalable movements.', exerciseIds: ['march_in_place', 'bodyweight_squat', 'glute_bridge']),
  _WorkoutPlan(id: 'intermediate_strength', name: 'Strength Builder', category: 'Strength', level: 'Intermediate', durationMinutes: 35, description: 'Combine compound movements for balanced full-body strength.', exerciseIds: ['bodyweight_squat', 'push_up', 'dumbbell_row', 'reverse_lunge', 'plank']),
  _WorkoutPlan(id: 'intermediate_cardio', name: 'Endurance Builder', category: 'Cardio', level: 'Intermediate', durationMinutes: 30, description: 'Develop aerobic endurance through steady, repeatable effort.', exerciseIds: ['brisk_walk', 'jogging', 'cycling']),
  _WorkoutPlan(id: 'intermediate_mobility', name: 'Movement and Mobility', category: 'Mobility', level: 'Intermediate', durationMinutes: 20, description: 'Work through controlled mobility drills for the hips and upper back.', exerciseIds: ['cat_cow', 'hip_flexor_stretch', 'thoracic_rotation', 'glute_bridge']),
  _WorkoutPlan(id: 'intermediate_conditioning', name: 'Conditioning Circuit', category: 'Conditioning', level: 'Intermediate', durationMinutes: 25, description: 'A mixed circuit with steady cardio and dynamic bodyweight work.', exerciseIds: ['high_knees', 'bodyweight_squat', 'mountain_climber', 'reverse_lunge']),
  _WorkoutPlan(id: 'advanced_strength', name: 'Advanced Bodyweight Strength', category: 'Strength', level: 'Advanced', durationMinutes: 40, description: 'A challenging bodyweight session. Scale repetitions to maintain sound technique.', exerciseIds: ['push_up', 'jump_squat', 'reverse_lunge', 'plank', 'mountain_climber']),
  _WorkoutPlan(id: 'advanced_cardio', name: 'Cardio Performance', category: 'Cardio', level: 'Advanced', durationMinutes: 40, description: 'A higher-effort endurance session for experienced participants.', exerciseIds: ['jogging', 'high_knees', 'cycling']),
  _WorkoutPlan(id: 'advanced_mobility', name: 'Extended Mobility Flow', category: 'Mobility', level: 'Advanced', durationMinutes: 25, description: 'A longer mobility sequence. Keep every movement controlled and pain-free.', exerciseIds: ['cat_cow', 'hip_flexor_stretch', 'thoracic_rotation', 'glute_bridge']),
  _WorkoutPlan(id: 'advanced_conditioning', name: 'Advanced Conditioning Circuit', category: 'Conditioning', level: 'Advanced', durationMinutes: 30, description: 'A demanding circuit combining explosive and core-focused movements.', exerciseIds: ['jump_squat', 'mountain_climber', 'high_knees', 'plank']),
];

class _GuidedWorkoutScreen extends StatefulWidget {
  const _GuidedWorkoutScreen({
    required this.exercises,
    required this.session,
    required this.initialIndex,
    required this.initialLogs,
    required this.isPaused,
    required this.onPauseChanged,
    super.key,
  });

  final List<_Exercise> exercises;
  final DocumentReference<Map<String, dynamic>> session;
  final int initialIndex;
  final List<Map<String, dynamic>> initialLogs;
  final bool isPaused;
  final Future<void> Function(bool pause) onPauseChanged;

  @override
  State<_GuidedWorkoutScreen> createState() => _GuidedWorkoutScreenState();
}

class _GuidedWorkoutScreenState extends State<_GuidedWorkoutScreen> {
  static const int _targetSets = 3;
  static const int _restDuration = 60;
  late int _index;
  late List<Map<String, dynamic>> _logs;
  final TextEditingController _repsController = TextEditingController(text: '10');
  final TextEditingController _weightController = TextEditingController(text: '0');
  final TextEditingController _durationController = TextEditingController(text: '30');
  Timer? _restTicker;
  int _restRemaining = 0;
  bool _saving = false;
  late bool _isPaused;

  _Exercise get _exercise => widget.exercises[_index];

  List<Map<String, dynamic>> get _currentSets {
    final entry = _logs.firstWhere(
      (item) => item['exerciseId'] == _exercise.id,
      orElse: () => <String, dynamic>{'sets': <Map<String, dynamic>>[]},
    );
    return (entry['sets'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.exercises.length - 1).toInt();
    _logs = widget.initialLogs.map((item) => Map<String, dynamic>.from(item)).toList();
    _isPaused = widget.isPaused;
  }

  @override
  void dispose() {
    _restTicker?.cancel();
    _repsController.dispose();
    _weightController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await widget.session.update({
      'currentExerciseIndex': _index,
      'exerciseLogs': _logs,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _updatePersonalRecord({
    required bool isTimed,
    required int? reps,
    required double? weight,
    required int? duration,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final profileRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('fitness_profile')
        .doc('current');

    return FirebaseFirestore.instance.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(profileRef);
      final profile = snapshot.data() ?? <String, dynamic>{};
      final records = profile['personalRecords'] is Map
          ? Map<String, dynamic>.from(profile['personalRecords'] as Map)
          : <String, dynamic>{};
      final previous = records[_exercise.id] is Map
          ? Map<String, dynamic>.from(records[_exercise.id] as Map)
          : <String, dynamic>{};

      var isNewRecord = false;
      final updated = <String, dynamic>{
        ...previous,
        'exerciseId': _exercise.id,
        'exerciseName': _exercise.name,
        'category': _exercise.category,
      };

      if (isTimed) {
        final oldDuration = (previous['bestDurationSeconds'] as num?)?.toInt() ?? 0;
        if ((duration ?? 0) > oldDuration) {
          updated['bestDurationSeconds'] = duration;
          isNewRecord = true;
        }
      } else {
        final oldWeight = (previous['bestWeightKg'] as num?)?.toDouble() ?? -1;
        final oldReps = (previous['bestReps'] as num?)?.toInt() ?? -1;
        final newWeight = weight ?? 0;
        final newReps = reps ?? 0;
        if (newWeight > oldWeight || (newWeight == oldWeight && newReps > oldReps)) {
          updated['bestWeightKg'] = newWeight;
          updated['bestReps'] = newReps;
          isNewRecord = true;
        }
      }

      if (isNewRecord) {
        updated['updatedAt'] = Timestamp.fromDate(DateTime.now());
        records[_exercise.id] = updated;
        transaction.set(profileRef, {
          'personalRecords': records,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return isNewRecord;
    });
  }

  Future<void> _completeSet() async {
    if (_saving) return;
    final isTimed = _exercise.category == 'Cardio' || _exercise.category == 'Mobility';
    final reps = int.tryParse(_repsController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    if ((isTimed && (duration == null || duration <= 0)) ||
        (!isTimed && (reps == null || reps < 0 || weight == null || !weight.isFinite || weight < 0))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid non-negative repetitions and weight.')),
      );
      return;
    }
    setState(() => _saving = true);
    final sets = _currentSets;
    sets.add({
      if (!isTimed) 'reps': reps,
      if (!isTimed) 'weightKg': weight,
      if (isTimed) 'durationSeconds': duration,
      'completedAt': Timestamp.fromDate(DateTime.now()),
    });
    final existingIndex = _logs.indexWhere((item) => item['exerciseId'] == _exercise.id);
    final updatedEntry = {'exerciseId': _exercise.id, 'sets': sets, 'completed': sets.length >= _targetSets};
    if (existingIndex >= 0) {
      _logs[existingIndex] = updatedEntry;
    } else {
      _logs.add(updatedEntry);
    }
    try {
      await _persist();
      var newRecord = false;
      var recordSyncFailed = false;
      try {
        newRecord = await _updatePersonalRecord(
          isTimed: isTimed,
          reps: reps,
          weight: weight,
          duration: duration,
        );
      } catch (_) {
        // A personal-record sync failure should not undo a successfully saved set.
        recordSyncFailed = true;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _restRemaining = sets.length < _targetSets ? _restDuration : 0;
      });
      if (_restRemaining > 0) _startRestTimer();
      if (newRecord) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New personal record: ${_exercise.name}!')),
        );
      } else if (recordSyncFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Set saved, but your personal record could not sync.')),
        );
      } else if (sets.length >= _targetSets) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exercise sets completed. Move to the next exercise when ready.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this set. Check your connection and try again.')),
      );
    }
  }

  void _startRestTimer() {
    _restTicker?.cancel();
    _restTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_restRemaining <= 1) {
        timer.cancel();
        setState(() => _restRemaining = 0);
      } else {
        setState(() => _restRemaining--);
      }
    });
  }

  void _skipRest() {
    _restTicker?.cancel();
    setState(() => _restRemaining = 0);
  }

  Future<void> _moveTo(int nextIndex) async {
    _restTicker?.cancel();
    final safeIndex = nextIndex.clamp(0, widget.exercises.length - 1).toInt();
    setState(() {
      _index = safeIndex;
      _restRemaining = 0;
      _repsController.text = '10';
      _weightController.text = '0';
      _durationController.text = '30';
    });
    try {
      await _persist();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress is visible but could not be synced.')),
        );
      }
    }
  }

  String _clock(int seconds) => '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final sets = _currentSets;
    final completedExercises = _logs.where((entry) => entry['completed'] == true).length;
    final progress = (completedExercises / widget.exercises.length).clamp(0.0, 1.0).toDouble();
    final isLast = _index == widget.exercises.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guided workout'),
        actions: [
          TextButton(onPressed: () async {
          final nextPaused = !_isPaused;
          await widget.onPauseChanged(nextPaused);
          if (!mounted) return;
          setState(() => _isPaused = nextPaused);
          if (nextPaused) {
            _restTicker?.cancel();
          } else if (_restRemaining > 0) {
            _startRestTimer();
          }
        }, child: Text(_isPaused ? 'Resume' : 'Pause')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_isPaused)
              Card(color: Theme.of(context).colorScheme.tertiaryContainer, child: const Padding(padding: EdgeInsets.all(12), child: Row(children: [Icon(Icons.pause_circle_outline), SizedBox(width: 8), Expanded(child: Text('Workout paused. Resume when you are ready.'))]))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Exercise ${_index + 1} of ${widget.exercises.length}', style: Theme.of(context).textTheme.labelLarge),
                Text('${(progress * 100).round()}% complete', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (_index + 1) / widget.exercises.length),
            const SizedBox(height: 24),
            Text(exercise.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              Chip(label: Text(exercise.category)),
              Chip(label: Text(exercise.equipment)),
              Chip(label: Text(exercise.level)),
            ]),
            const SizedBox(height: 12),
            Text(exercise.description),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('How to perform it', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...exercise.instructions.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      CircleAvatar(radius: 12, child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entry.value)),
                    ]),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            Text('Set ${sets.length + 1} of $_targetSets', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (exercise.category == 'Cardio' || exercise.category == 'Mobility')
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Duration (seconds)', border: OutlineInputBorder()),
              )
            else
              Row(children: [
                Expanded(child: TextField(
                  controller: _repsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repetitions', border: OutlineInputBorder()),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _weightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
                )),
              ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isPaused || _saving || sets.length >= _targetSets ? null : _completeSet,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: Text(_saving ? 'Saving set...' : sets.length >= _targetSets ? 'All sets completed' : 'Complete set'),
            ),
            if (sets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Completed sets', style: Theme.of(context).textTheme.titleSmall),
              ...sets.asMap().entries.map((entry) => ListTile(
                dense: true,
                leading: CircleAvatar(child: Text('${entry.key + 1}')),
                title: Text(entry.value['durationSeconds'] != null
                    ? '${entry.value['durationSeconds']} seconds'
                    : '${entry.value['reps'] ?? 0} reps'),
                trailing: Text(entry.value['weightKg'] == null ? '' : '${entry.value['weightKg']} kg'),
              )),
            ],
            if (_restRemaining > 0) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text('Rest', style: Theme.of(context).textTheme.titleMedium),
                    Text(_clock(_restRemaining), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold)),
                    TextButton.icon(onPressed: _skipRest, icon: const Icon(Icons.skip_next), label: const Text('Skip rest')),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _index == 0 ? null : () => _moveTo(_index - 1),
                icon: const Icon(Icons.chevron_left), label: const Text('Previous'),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(
                onPressed: isLast ? () => Navigator.pop(context) : () => _moveTo(_index + 1),
                icon: Icon(isLast ? Icons.check_circle_outline : Icons.skip_next),
                label: Text(isLast ? 'Done' : 'Next exercise'),
              )),
            ]),
            const SizedBox(height: 12),
            Text('Your sets and current exercise are saved as you go. You can close this screen and resume later.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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





class _LiveGpsRouteMap extends StatefulWidget {
  const _LiveGpsRouteMap({
    required this.points,
    required this.currentPosition,
  });

  final List<Map<String, dynamic>> points;
  final Position currentPosition;

  @override
  State<_LiveGpsRouteMap> createState() => _LiveGpsRouteMapState();
}

class _LiveGpsRouteMapState extends State<_LiveGpsRouteMap> {
  late final MapController _mapController;
  bool _followCurrentPosition = true;
  double _zoom = 16;

  LatLng get _currentPoint => LatLng(
        widget.currentPosition.latitude,
        widget.currentPosition.longitude,
      );

  List<LatLng> get _routeCoordinates => widget.points
      .where((point) => point['latitude'] is num && point['longitude'] is num)
      .map((point) => LatLng(
            (point['latitude'] as num).toDouble(),
            (point['longitude'] as num).toDouble(),
          ))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(covariant _LiveGpsRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_followCurrentPosition &&
        (oldWidget.currentPosition.latitude != widget.currentPosition.latitude ||
            oldWidget.currentPosition.longitude != widget.currentPosition.longitude)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_followCurrentPosition) return;
        _mapController.move(_currentPoint, _zoom);
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _recenter() {
    setState(() => _followCurrentPosition = true);
    _mapController.move(_currentPoint, _zoom);
  }

  @override
  Widget build(BuildContext context) {
    final coordinates = _routeCoordinates;
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPoint,
            initialZoom: _zoom,
            minZoom: 3,
            maxZoom: 19,
            onPositionChanged: (camera, hasGesture) {
              _zoom = camera.zoom;
              if (hasGesture && _followCurrentPosition) {
                setState(() => _followCurrentPosition = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.test_ap_1',
            ),
            if (coordinates.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: coordinates,
                    color: Theme.of(context).colorScheme.primary,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (coordinates.isNotEmpty)
                  Marker(
                    point: coordinates.first,
                    width: 26,
                    height: 26,
                    child: const Icon(Icons.trip_origin, color: Colors.green, size: 20),
                  ),
                Marker(
                  point: _currentPoint,
                  width: 42,
                  height: 42,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.navigation, color: Theme.of(context).colorScheme.primary, size: 26),
                  ),
                ),
              ],
            ),
            RichAttributionWidget(
              attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
        Positioned(
          right: 10,
          top: 10,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 3,
            child: IconButton(
              tooltip: 'Recenter on current location',
              onPressed: _recenter,
              icon: Icon(
                _followCurrentPosition ? Icons.my_location : Icons.location_searching,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(
                _followCurrentPosition ? 'Following location' : 'Map moved · tap locate to follow',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GpsRouteMap extends StatelessWidget {
  const _GpsRouteMap({
    required this.points,
    required this.routeColor,
  });

  final List<Map<String, dynamic>> points;
  final Color routeColor;

  @override
  Widget build(BuildContext context) {
    final coordinates = points.map((point) {
      return LatLng(
        (point['latitude'] as num).toDouble(),
        (point['longitude'] as num).toDouble(),
      );
    }).toList(growable: false);

    if (coordinates.length < 2) {
      return const Center(child: Text('Not enough route points to display a map.'));
    }

    var minLatitude = coordinates.first.latitude;
    var maxLatitude = coordinates.first.latitude;
    var minLongitude = coordinates.first.longitude;
    var maxLongitude = coordinates.first.longitude;

    for (final coordinate in coordinates.skip(1)) {
      if (coordinate.latitude < minLatitude) minLatitude = coordinate.latitude;
      if (coordinate.latitude > maxLatitude) maxLatitude = coordinate.latitude;
      if (coordinate.longitude < minLongitude) minLongitude = coordinate.longitude;
      if (coordinate.longitude > maxLongitude) maxLongitude = coordinate.longitude;
    }

    // Give stationary or nearly straight routes a little breathing room so
    // the initial camera fit never receives zero-sized bounds.
    const minimumSpan = 0.001;
    if (maxLatitude - minLatitude < minimumSpan) {
      final center = (maxLatitude + minLatitude) / 2;
      minLatitude = center - minimumSpan / 2;
      maxLatitude = center + minimumSpan / 2;
    }
    if (maxLongitude - minLongitude < minimumSpan) {
      final center = (maxLongitude + minLongitude) / 2;
      minLongitude = center - minimumSpan / 2;
      maxLongitude = center + minimumSpan / 2;
    }

    final bounds = LatLngBounds.fromPoints([
      LatLng(minLatitude, minLongitude),
      LatLng(maxLatitude, maxLongitude),
    ]);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(34),
        ),
        minZoom: 3,
        maxZoom: 19,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // Use the app's Android application ID, not a generic package name.
          userAgentPackageName: 'com.example.test_ap_1',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: coordinates,
              color: routeColor,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: coordinates.first,
              width: 34,
              height: 34,
              child: const Icon(Icons.location_on, color: Colors.green, size: 32),
            ),
            Marker(
              point: coordinates.last,
              width: 34,
              height: 34,
              child: const Icon(Icons.flag_rounded, color: Colors.red, size: 28),
            ),
          ],
        ),
        RichAttributionWidget(
          attributions: const [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}


extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
