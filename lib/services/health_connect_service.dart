import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

/// A small, read-only bridge between Trailblazer and Android Health Connect.
/// Health measurements remain in Health Connect; this service does not copy
/// personal health data into Firestore.
class HealthConnectService {
  HealthConnectService({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  static const List<HealthDataType> _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
  ];

  static const List<HealthDataAccess> _readAccess = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  bool get isPlatformSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Returns true only when the Health Connect provider is available.
  Future<bool> isAvailable() async {
    await initialize();
    if (!isPlatformSupported) return false;

    final status = await _health.getHealthConnectSdkStatus();
    return status == HealthConnectSdkStatus.sdkAvailable;
  }

  /// Checks the current read grants. Health Connect grants can be revoked
  /// outside the app, so this is checked again before each data read.
  Future<bool> hasReadAccess() async {
    await initialize();
    if (!isPlatformSupported) return false;

    return await _health.hasPermissions(
          _readTypes,
          permissions: _readAccess,
        ) ??
        false;
  }

  /// Requests only the permissions needed for today's steps and distance.
  Future<bool> requestReadAccess() async {
    await initialize();

    if (!isPlatformSupported) {
      throw UnsupportedError('Health Connect is currently configured for Android.');
    }

    final available = await isAvailable();
    if (!available) {
      throw StateError(
        'Health Connect is not available. Install or update Health Connect, then try again.',
      );
    }

    final activityPermission = await Permission.activityRecognition.request();
    if (!activityPermission.isGranted) {
      throw StateError(
        'Activity recognition permission is needed to read step data. You can enable it in Android app settings.',
      );
    }

    return _health.requestAuthorization(
      _readTypes,
      permissions: _readAccess,
    );
  }

  /// Reads today's step total and walking-distance samples.
  Future<DailyHealthMetrics> readToday() async {
    await initialize();

    if (!isPlatformSupported) {
      throw UnsupportedError('Health Connect is currently configured for Android.');
    }

    if (!await hasReadAccess()) {
      throw StateError('Health Connect access is not currently granted.');
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final steps = await _health.getTotalStepsInInterval(startOfDay, now) ?? 0;

    // Ask Health Connect for a native daily aggregate rather than summing raw
    // records from multiple sources, which can overlap.
    final distancePoints = await _health.getHealthIntervalDataFromTypes(
      types: const [HealthDataType.DISTANCE_DELTA],
      startDate: startOfDay,
      endDate: now,
      interval: 24 * 60 * 60,
    );

    final distanceMeters = distancePoints.fold<double>(
      0,
      (total, point) {
        final value = point.value;
        if (value is NumericHealthValue) {
          return total + value.numericValue;
        }
        return total;
      },
    );

    return DailyHealthMetrics(
      steps: steps,
      walkingDistanceKm: distanceMeters / 1000,
      measuredAt: now,
    );
  }

  /// Opens the Health Connect installation/update flow when supported.
  Future<void> installOrUpdateHealthConnect() async {
    await initialize();
    if (!isPlatformSupported) return;
    await _health.installHealthConnect();
  }
}

class DailyHealthMetrics {
  const DailyHealthMetrics({
    required this.steps,
    required this.walkingDistanceKm,
    required this.measuredAt,
  });

  final int steps;
  final double walkingDistanceKm;
  final DateTime measuredAt;
}
