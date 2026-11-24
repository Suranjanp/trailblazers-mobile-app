import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

/// Provides a small, read-only bridge between Trailblazer and Android Health
/// Connect.
///
/// Health measurements remain in Health Connect. This service reads the
/// requested activity metrics for display in the app and does not copy personal
/// health data into Firestore.
class HealthConnectService {
  /// Creates the service, optionally accepting a Health client for testing.
  ///
  /// Supplying [health] allows callers or tests to inject a configured client;
  /// otherwise the service creates its own [Health] instance.
  HealthConnectService({Health? health}) : _health = health ?? Health();

  // Health Connect SDK client used for configuration, permission checks,
  // authorization requests, and metric retrieval.
  final Health _health;

  // The Health client only needs to be configured once per service instance.
  bool _configured = false;

  // Keep the requested data scope intentionally narrow: the dashboard needs
  // today's step count and walking-distance total, and does not need write access.
  static const List<HealthDataType> _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
  ];

  // Access entries correspond by index to _readTypes above. Both data types
  // are requested with read-only access.
  static const List<HealthDataAccess> _readAccess = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  /// Whether this implementation can use Health Connect on the current device.
  ///
  /// Health Connect integration is limited to Android and is not supported on
  /// Flutter web.
  bool get isPlatformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Configures the underlying Health SDK once for this service instance.
  Future<void> initialize() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Returns true only when the Health Connect provider is available.
  ///
  /// Configuration is performed first, and unsupported platforms return
  /// false without attempting to query the Android provider.
  Future<bool> isAvailable() async {
    await initialize();
    if (!isPlatformSupported) return false;

    final status = await _health.getHealthConnectSdkStatus();
    return status == HealthConnectSdkStatus.sdkAvailable;
  }

  /// Checks whether the app currently has read grants for the requested data.
  ///
  /// Health Connect permissions can be revoked in Android settings or outside
  /// the app, so the service checks the current grants before each data read.
  Future<bool> hasReadAccess() async {
    await initialize();
    if (!isPlatformSupported) return false;

    return await _health.hasPermissions(
          _readTypes,
          permissions: _readAccess,
        ) ??
        false;
  }

  /// Requests the Android and Health Connect permissions needed for today's
  /// steps and walking distance.
  ///
  /// Throws a descriptive error when the platform is unsupported, the provider
  /// is unavailable, or Android activity-recognition permission is denied.
  /// The final authorization request asks Health Connect for read access only.
  Future<bool> requestReadAccess() async {
    await initialize();

    if (!isPlatformSupported) {
      throw UnsupportedError('Health Connect is currently configured for Android.');
    }

    // Verify that the provider is installed and ready before opening permission
    // flows, so the user receives a useful error when setup is required.
    final available = await isAvailable();
    if (!available) {
      throw StateError(
        'Health Connect is not available. Install or update Health Connect, then try again.',
      );
    }

    // Android requires activity-recognition permission for step-related data.
    final activityPermission = await Permission.activityRecognition.request();
    if (!activityPermission.isGranted) {
      throw StateError(
        'Activity recognition permission is needed to read step data. You can enable it in Android app settings.',
      );
    }

    // Request only the two data types declared above, with read-only access.
    return _health.requestAuthorization(
      _readTypes,
      permissions: _readAccess,
    );
  }

  /// Reads today's step total and walking-distance samples from Health Connect.
  ///
  /// The method validates platform support and current grants before querying.
  /// The returned distance is normalized to kilometers so the rest of the app
  /// can apply the user's selected display units separately.
  Future<DailyHealthMetrics> readToday() async {
    await initialize();

    if (!isPlatformSupported) {
      throw UnsupportedError('Health Connect is currently configured for Android.');
    }

    if (!await hasReadAccess()) {
      throw StateError('Health Connect access is not currently granted.');
    }

    // Limit both metrics to the current local calendar day.
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    // Use the SDK's interval total for steps rather than manually summing
    // individual step records.
    final steps = await _health.getTotalStepsInInterval(startOfDay, now) ?? 0;

    // Ask Health Connect for a native daily aggregate rather than summing raw
    // records from multiple sources, which can overlap.
    final distancePoints = await _health.getHealthIntervalDataFromTypes(
      types: const [HealthDataType.DISTANCE_DELTA],
      startDate: startOfDay,
      endDate: now,
      interval: 24 * 60 * 60,
    );

    // Sum numeric distance values returned for the requested interval.
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

    // Normalize meters to kilometers for consistent internal storage and
    // formatting across metric and imperial app settings.
    return DailyHealthMetrics(
      steps: steps,
      walkingDistanceKm: distanceMeters / 1000,
      measuredAt: now,
    );
  }

  /// Opens the Health Connect installation or update flow when supported.
  ///
  /// On unsupported platforms this method safely returns without doing anything.
  Future<void> installOrUpdateHealthConnect() async {
    await initialize();
    if (!isPlatformSupported) return;
    await _health.installHealthConnect();
  }
}

/// Immutable result object containing the daily metrics read from Health Connect.
///
/// [walkingDistanceKm] is always expressed in kilometers, independent of the
/// user's display preference. [measuredAt] records when the read completed.
class DailyHealthMetrics {
  const DailyHealthMetrics({
    required this.steps,
    required this.walkingDistanceKm,
    required this.measuredAt,
  });

  /// Total steps recorded from the start of the current day to the read time.
  final int steps;

  /// Walking distance for the same interval, normalized to kilometers.
  final double walkingDistanceKm;

  /// Local timestamp associated with this metrics read.
  final DateTime measuredAt;
}
