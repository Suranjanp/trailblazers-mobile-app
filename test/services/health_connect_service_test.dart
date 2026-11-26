import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:test_ap_1/services/health_connect_service.dart';

class _MockHealth extends Mock implements Health {}

class _MockHealthDataPoint extends Mock implements HealthDataPoint {}

class _MockNumericHealthValue extends Mock implements NumericHealthValue {}

class _MockOtherHealthValue extends Mock implements HealthValue {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  const readTypes = [HealthDataType.STEPS, HealthDataType.DISTANCE_DELTA];

  const readAccess = [HealthDataAccess.READ, HealthDataAccess.READ];

  late _MockHealth health;
  late HealthConnectService service;

  late PermissionStatus activityPermission;
  late List<MethodCall> permissionCalls;

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    health = _MockHealth();
    service = HealthConnectService(health: health);

    activityPermission = PermissionStatus.granted;
    permissionCalls = [];

    // Replace the Android permission plugin with an in-memory response.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          permissionCalls.add(call);

          if (call.method == 'requestPermissions') {
            return <int, int>{
              Permission.activityRecognition.value: activityPermission.index,
            };
          }

          throw MissingPluginException(
            'Unexpected permission method: ${call.method}',
          );
        });

    when(() => health.configure()).thenAnswer((_) async {});

    when(() => health.getHealthConnectSdkStatus())
        .thenAnswer((_) async => HealthConnectSdkStatus.sdkAvailable);

    when(() => health.hasPermissions(readTypes, permissions: readAccess))
        .thenAnswer((_) async => true);

    when(() => health.requestAuthorization(readTypes, permissions: readAccess))
        .thenAnswer((_) async => true);

    when(() => health.getTotalStepsInInterval(any(), any()))
        .thenAnswer((_) async => 4200);

    when(
      () => health.getHealthIntervalDataFromTypes(
        types: const [HealthDataType.DISTANCE_DELTA],
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        interval: 86400,
      ),
    ).thenAnswer((_) async => <HealthDataPoint>[]);

    when(() => health.installHealthConnect()).thenAnswer((_) async {});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);

    debugDefaultTargetPlatformOverride = null;
  });

  HealthDataPoint distancePoint(num meters) {
    final value = _MockNumericHealthValue();
    when(() => value.numericValue).thenReturn(meters);

    final point = _MockHealthDataPoint();
    when(() => point.value).thenReturn(value);

    return point;
  }

  void returnDistancePoints(List<HealthDataPoint> points) {
    when(
      () => health.getHealthIntervalDataFromTypes(
        types: const [HealthDataType.DISTANCE_DELTA],
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        interval: 86400,
      ),
    ).thenAnswer((_) async => points);
  }

  void expectNoMetricReads() {
    verifyNever(() => health.getTotalStepsInInterval(any(), any()));

    verifyNever(
      () => health.getHealthIntervalDataFromTypes(
        types: const [HealthDataType.DISTANCE_DELTA],
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        interval: 86400,
      ),
    );
  }

  group('Platform support', () {
    test('supports Android in native tests', () {
      expect(service.isPlatformSupported, isTrue);
    });

    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      test('does not support ${platform.name}', () {
        debugDefaultTargetPlatformOverride = platform;

        expect(service.isPlatformSupported, isFalse);
      });
    }
  });

  group('Initialization', () {
    test(
      'configures the Health client only once across sequential calls',
      () async {
        await service.initialize();
        await service.initialize();
        await service.isAvailable();
        await service.hasReadAccess();

        verify(() => health.configure()).called(1);
      },
    );

    test('propagates configuration failure and allows a later retry', () async {
      final failure = StateError('Configuration failed');

      when(() => health.configure()).thenThrow(failure);

      await expectLater(service.initialize(), throwsA(same(failure)));

      when(() => health.configure()).thenAnswer((_) async {});

      await service.initialize();
      await service.initialize();

      // One failed attempt followed by one successful attempt.
      verify(() => health.configure()).called(2);
    });
  });

  group('Provider availability', () {
    test('returns true when the provider is available', () async {
      expect(await service.isAvailable(), isTrue);

      verify(() => health.configure()).called(1);
      verify(() => health.getHealthConnectSdkStatus()).called(1);
    });

    for (final status in HealthConnectSdkStatus.values) {
      if (status == HealthConnectSdkStatus.sdkAvailable) continue;

      test('returns false for provider status ${status.name}', () async {
        when(() => health.getHealthConnectSdkStatus())
            .thenAnswer((_) async => status);

        expect(await service.isAvailable(), isFalse);
      });
    }

    test('unsupported platforms do not query provider status', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(await service.isAvailable(), isFalse);

      // The supplied implementation configures before checking platform.
      verify(() => health.configure()).called(1);
      verifyNever(() => health.getHealthConnectSdkStatus());
    });
  });

  group('Read-access checks', () {
    test('checks exactly steps and distance with read-only access', () async {
      expect(await service.hasReadAccess(), isTrue);

      verify(() => health.hasPermissions(readTypes, permissions: readAccess))
          .called(1);
    });

    test('returns false when permissions are denied', () async {
      when(() => health.hasPermissions(readTypes, permissions: readAccess))
          .thenAnswer((_) async => false);

      expect(await service.hasReadAccess(), isFalse);
    });

    test('treats an unknown permission result as denied', () async {
      when(() => health.hasPermissions(readTypes, permissions: readAccess))
          .thenAnswer((_) async => null);

      expect(await service.hasReadAccess(), isFalse);
    });

    test('unsupported platforms do not query Health permissions', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(await service.hasReadAccess(), isFalse);

      verifyNever(
        () => health.hasPermissions(readTypes, permissions: readAccess),
      );
    });
  });

  group('Requesting read access', () {
    test(
      'rejects unsupported platforms without requesting permissions',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        await expectLater(
          service.requestReadAccess(),
          throwsA(isA<UnsupportedError>()),
        );

        expect(permissionCalls, isEmpty);
        verifyNever(() => health.getHealthConnectSdkStatus());

        verifyNever(
          () => health.requestAuthorization(readTypes, permissions: readAccess),
        );
      },
    );

    test(
      'rejects an unavailable provider before Android permission flow',
      () async {
        final unavailableStatus = HealthConnectSdkStatus.values.firstWhere(
          (status) => status != HealthConnectSdkStatus.sdkAvailable,
        );

        when(() => health.getHealthConnectSdkStatus())
            .thenAnswer((_) async => unavailableStatus);

        await expectLater(
          service.requestReadAccess(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Health Connect is not available'),
            ),
          ),
        );

        expect(permissionCalls, isEmpty);

        verifyNever(
          () => health.requestAuthorization(readTypes, permissions: readAccess),
        );
      },
    );

    for (final deniedStatus in [
      PermissionStatus.denied,
      PermissionStatus.permanentlyDenied,
    ]) {
      test('rejects activity recognition ${deniedStatus.name}', () async {
        activityPermission = deniedStatus;

        await expectLater(
          service.requestReadAccess(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Activity recognition permission is needed'),
            ),
          ),
        );

        verifyNever(
          () => health.requestAuthorization(readTypes, permissions: readAccess),
        );
      });
    }

    test('requests activity recognition and read-only Health access', () async {
      expect(await service.requestReadAccess(), isTrue);

      expect(permissionCalls, hasLength(1));
      expect(permissionCalls.single.method, 'requestPermissions');
      expect(permissionCalls.single.arguments, [
        Permission.activityRecognition.value,
      ]);

      verify(
        () => health.requestAuthorization(readTypes, permissions: readAccess),
      ).called(1);

      expectNoMetricReads();
    });

    test('returns false when Health authorization is declined', () async {
      when(
        () => health.requestAuthorization(readTypes, permissions: readAccess),
      ).thenAnswer((_) async => false);

      expect(await service.requestReadAccess(), isFalse);
      expectNoMetricReads();
    });
  });

  group('Reading daily metrics', () {
    test(
      'returns steps and converts summed numeric meters to kilometers',
      () async {
        returnDistancePoints([distancePoint(1250), distancePoint(750.5)]);

        final metrics = await service.readToday();

        expect(metrics.steps, 4200);
        expect(metrics.walkingDistanceKm, closeTo(2.0005, 0.000001));
      },
    );

    test('uses zero when the SDK returns no step total', () async {
      when(() => health.getTotalStepsInInterval(any(), any()))
          .thenAnswer((_) async => null);

      final metrics = await service.readToday();

      expect(metrics.steps, 0);
      expect(metrics.walkingDistanceKm, 0);
    });

    test('ignores distance points with nonnumeric values', () async {
      final nonnumericPoint = _MockHealthDataPoint();
      when(() => nonnumericPoint.value).thenReturn(_MockOtherHealthValue());

      returnDistancePoints([
        distancePoint(1000),
        nonnumericPoint,
        distancePoint(500),
      ]);

      final metrics = await service.readToday();

      expect(metrics.walkingDistanceKm, closeTo(1.5, 0.000001));
    });

    test('uses the same local-day interval for steps and distance', () async {
      DateTime? stepStart;
      DateTime? stepEnd;
      DateTime? distanceStart;
      DateTime? distanceEnd;

      when(() => health.getTotalStepsInInterval(any(), any()))
          .thenAnswer((invocation) async {
            stepStart = invocation.positionalArguments[0] as DateTime;
            stepEnd = invocation.positionalArguments[1] as DateTime;
            return 100;
          });

      when(
        () => health.getHealthIntervalDataFromTypes(
          types: const [HealthDataType.DISTANCE_DELTA],
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          interval: 86400,
        ),
      ).thenAnswer((invocation) async {
        distanceStart = invocation.namedArguments[#startDate] as DateTime;
        distanceEnd = invocation.namedArguments[#endDate] as DateTime;
        return <HealthDataPoint>[];
      });

      final before = DateTime.now();
      final metrics = await service.readToday();
      final after = DateTime.now();

      expect(stepStart, isNotNull);
      expect(stepEnd, isNotNull);
      expect(distanceStart, stepStart);
      expect(distanceEnd, stepEnd);

      final end = stepEnd!;
      expect(stepStart, DateTime(end.year, end.month, end.day));
      expect(stepStart!.isUtc, isFalse);
      expect(end.isBefore(before), isFalse);
      expect(end.isAfter(after), isFalse);

      // Current implementation records the read's interval end time.
      expect(metrics.measuredAt, end);
    });

    test('rejects unsupported platforms before reading metrics', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await expectLater(service.readToday(), throwsA(isA<UnsupportedError>()));

      expectNoMetricReads();
    });

    test('rejects missing access before reading metrics', () async {
      when(() => health.hasPermissions(readTypes, permissions: readAccess))
          .thenAnswer((_) async => false);

      await expectLater(
        service.readToday(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('access is not currently granted'),
          ),
        ),
      );

      expectNoMetricReads();
    });

    test(
      'checks permissions again when access is revoked between reads',
      () async {
        await service.readToday();

        when(() => health.hasPermissions(readTypes, permissions: readAccess))
            .thenAnswer((_) async => false);

        await expectLater(service.readToday(), throwsA(isA<StateError>()));

        verify(() => health.hasPermissions(readTypes, permissions: readAccess))
            .called(2);

        // Only the first authorized read should reach the data methods.
        verify(() => health.getTotalStepsInInterval(any(), any())).called(1);

        verify(
          () => health.getHealthIntervalDataFromTypes(
            types: const [HealthDataType.DISTANCE_DELTA],
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            interval: 86400,
          ),
        ).called(1);
      },
    );

    test('propagates step-reading failures', () async {
      final failure = StateError('Step read failed');

      when(() => health.getTotalStepsInInterval(any(), any()))
          .thenThrow(failure);

      await expectLater(service.readToday(), throwsA(same(failure)));

      verifyNever(
        () => health.getHealthIntervalDataFromTypes(
          types: const [HealthDataType.DISTANCE_DELTA],
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          interval: 86400,
        ),
      );
    });

    test('propagates distance-reading failures', () async {
      final failure = StateError('Distance read failed');

      when(
        () => health.getHealthIntervalDataFromTypes(
          types: const [HealthDataType.DISTANCE_DELTA],
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          interval: 86400,
        ),
      ).thenThrow(failure);

      await expectLater(service.readToday(), throwsA(same(failure)));
    });
  });

  group('Health Connect installation', () {
    test('opens installation on Android', () async {
      await service.installOrUpdateHealthConnect();

      verify(() => health.configure()).called(1);
      verify(() => health.installHealthConnect()).called(1);
    });

    test('does not open installation on unsupported platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await service.installOrUpdateHealthConnect();

      verifyNever(() => health.installHealthConnect());
    });

    test('propagates installation failures', () async {
      final failure = StateError('Installation failed');

      when(() => health.installHealthConnect()).thenThrow(failure);

      await expectLater(
        service.installOrUpdateHealthConnect(),
        throwsA(same(failure)),
      );
    });
  });

  group('DailyHealthMetrics', () {
    test('retains the supplied metrics and timestamp', () {
      final timestamp = DateTime(2026, 11, 25, 14, 30);

      final metrics = DailyHealthMetrics(
        steps: 7500,
        walkingDistanceKm: 5.25,
        measuredAt: timestamp,
      );

      expect(metrics.steps, 7500);
      expect(metrics.walkingDistanceKm, 5.25);
      expect(metrics.measuredAt, timestamp);
    });
  });
}