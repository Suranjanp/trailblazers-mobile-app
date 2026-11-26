import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_ap_1/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final settings = AppSettings.instance;

  const darkModeKey = 'settings_dark_mode';
  const measurementKey = 'settings_measurement_system';

  // AppSettings is a singleton. Reset its storage and in-memory state
  // before every test so test order cannot affect the results.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.load();
  });

  group('AppSettings loading', () {
    test('uses light theme and metric units when nothing is saved', () {
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.isDarkMode, isFalse);
      expect(settings.measurementSystem, MeasurementSystem.metric);
      expect(settings.isMetric, isTrue);
    });

    for (final dark in [false, true]) {
      for (final system in MeasurementSystem.values) {
        test('loads dark=$dark and ${system.name} together', () async {
          SharedPreferences.setMockInitialValues({
            darkModeKey: dark,
            measurementKey: system.name,
          });

          await settings.load();

          expect(settings.themeMode, dark ? ThemeMode.dark : ThemeMode.light);
          expect(settings.isDarkMode, dark);
          expect(settings.measurementSystem, system);
          expect(settings.isMetric, system == MeasurementSystem.metric);
        });
      }
    }

    test('missing preferences replace previously loaded settings', () async {
      await settings.setDarkMode(true);
      await settings.setMeasurementSystem(MeasurementSystem.imperial);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      await settings.load();

      expect(settings.themeMode, ThemeMode.light);
      expect(settings.measurementSystem, MeasurementSystem.metric);
    });

    for (final invalid in <Object>[
      'true',
      1,
      1.5,
      <String>['true'],
    ]) {
      test('invalid dark-mode value $invalid falls back to light', () async {
        SharedPreferences.setMockInitialValues({
          darkModeKey: invalid,
          measurementKey: 'imperial',
        });

        await settings.load();

        expect(settings.themeMode, ThemeMode.light);
        expect(settings.isDarkMode, isFalse);

        // An invalid theme must not prevent valid units from loading.
        expect(settings.measurementSystem, MeasurementSystem.imperial);
      });
    }

    for (final invalid in <Object>['unknown', 'Imperial', '', true, 42, 2.5]) {
      test('invalid measurement value $invalid falls back to metric', () async {
        SharedPreferences.setMockInitialValues({
          darkModeKey: true,
          measurementKey: invalid,
        });

        await settings.load();

        expect(settings.measurementSystem, MeasurementSystem.metric);
        expect(settings.isMetric, isTrue);
        expect(settings.themeMode, ThemeMode.dark);
      });
    }

    test('notifies once after both saved settings are restored', () async {
      SharedPreferences.setMockInitialValues({
        darkModeKey: true,
        measurementKey: 'imperial',
      });

      final observedStates = <(ThemeMode, MeasurementSystem)>[];

      void listener() {
        observedStates.add((settings.themeMode, settings.measurementSystem));
      }

      settings.addListener(listener);
      addTearDown(() => settings.removeListener(listener));

      await settings.load();

      expect(observedStates, [(ThemeMode.dark, MeasurementSystem.imperial)]);
    });
  });

  group('AppSettings updates and persistence', () {
    test(
      'dark mode updates immediately and notifies before completion',
      () async {
        final observed = <ThemeMode>[];

        void listener() => observed.add(settings.themeMode);

        settings.addListener(listener);
        addTearDown(() => settings.removeListener(listener));

        final pendingWrite = settings.setDarkMode(true);

        expect(settings.themeMode, ThemeMode.dark);
        expect(settings.isDarkMode, isTrue);
        expect(observed, [ThemeMode.dark]);

        await pendingWrite;

        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getBool(darkModeKey), isTrue);
      },
    );

    test('turning dark mode off persists false', () async {
      await settings.setDarkMode(true);
      await settings.setDarkMode(false);

      final preferences = await SharedPreferences.getInstance();

      expect(settings.themeMode, ThemeMode.light);
      expect(settings.isDarkMode, isFalse);
      expect(preferences.getBool(darkModeKey), isFalse);
    });

    test('measurement change updates immediately and notifies', () async {
      final observed = <MeasurementSystem>[];

      void listener() => observed.add(settings.measurementSystem);

      settings.addListener(listener);
      addTearDown(() => settings.removeListener(listener));

      final pendingWrite = settings.setMeasurementSystem(
        MeasurementSystem.imperial,
      );

      expect(settings.measurementSystem, MeasurementSystem.imperial);
      expect(settings.isMetric, isFalse);
      expect(observed, [MeasurementSystem.imperial]);

      await pendingWrite;

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(measurementKey), 'imperial');
    });

    test('switching back to metric persists metric', () async {
      await settings.setMeasurementSystem(MeasurementSystem.imperial);
      await settings.setMeasurementSystem(MeasurementSystem.metric);

      final preferences = await SharedPreferences.getInstance();

      expect(settings.isMetric, isTrue);
      expect(preferences.getString(measurementKey), 'metric');
    });

    test('changing theme preserves the selected measurement system', () async {
      await settings.setMeasurementSystem(MeasurementSystem.imperial);
      await settings.setDarkMode(true);

      final preferences = await SharedPreferences.getInstance();

      expect(settings.measurementSystem, MeasurementSystem.imperial);
      expect(preferences.getString(measurementKey), 'imperial');
    });

    test('changing units preserves the selected theme', () async {
      await settings.setDarkMode(true);
      await settings.setMeasurementSystem(MeasurementSystem.imperial);

      final preferences = await SharedPreferences.getInstance();

      expect(settings.themeMode, ThemeMode.dark);
      expect(preferences.getBool(darkModeKey), isTrue);
    });

    test('saved choices survive a subsequent load', () async {
      await settings.setDarkMode(true);
      await settings.setMeasurementSystem(MeasurementSystem.imperial);

      await settings.load();

      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.measurementSystem, MeasurementSystem.imperial);
    });

    test('saving settings preserves unrelated preferences', () async {
      SharedPreferences.setMockInitialValues({'unrelated_setting': 'keep me'});
      await settings.load();

      await settings.setDarkMode(true);
      await settings.setMeasurementSystem(MeasurementSystem.imperial);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('unrelated_setting'), 'keep me');
    });
  });

  group('Metric conversions and labels', () {
    test('uses metric labels', () {
      expect(settings.distanceUnit, 'km');
      expect(settings.weightUnit, 'kg');
      expect(settings.heightUnit, 'cm');
    });

    test('distance display and entry keep kilometers unchanged', () {
      expect(settings.displayDistanceFromKm(5.25), 5.25);
      expect(settings.enteredDistanceToKm(5.25), 5.25);
      expect(settings.displayDistanceFromKm(0), 0);
    });

    test('formats distances with default and custom precision', () {
      expect(settings.formatDistanceFromKm(5.678), '5.68 km');
      expect(settings.formatDistanceFromKm(5.678, decimals: 1), '5.7 km');
      expect(settings.formatDistanceFromKm(0), '0.00 km');
    });

    test('speed stays in km/h and formats correctly', () {
      expect(settings.displaySpeedFromKmh(12.34), 12.34);
      expect(settings.formatSpeedFromKmh(12.34), '12.3 km/h');
      expect(settings.formatSpeedFromKmh(12.34, decimals: 2), '12.34 km/h');
    });

    test('elevation stays in meters and formats correctly', () {
      expect(settings.displayElevationFromMeters(123.4), 123.4);
      expect(settings.formatElevationFromMeters(123.4), '123 m');
      expect(settings.formatElevationFromMeters(123.4, decimals: 1), '123.4 m');
      expect(settings.formatElevationFromMeters(-10), '-10 m');
    });
  });

  group('Imperial conversions and labels', () {
    setUp(() async {
      await settings.setMeasurementSystem(MeasurementSystem.imperial);
    });

    test('uses imperial labels', () {
      expect(settings.distanceUnit, 'mi');
      expect(settings.weightUnit, 'lb');
      expect(settings.heightUnit, 'ft / in');
    });

    test('converts kilometers to miles', () {
      expect(settings.displayDistanceFromKm(10), closeTo(6.21371, 0.000001));
      expect(settings.displayDistanceFromKm(0), 0);
      expect(settings.formatDistanceFromKm(10), '6.21 mi');
      expect(settings.formatDistanceFromKm(10, decimals: 3), '6.214 mi');
    });

    test('converts entered miles back to kilometers', () {
      expect(settings.enteredDistanceToKm(1), closeTo(1.609344, 0.00001));
      expect(settings.enteredDistanceToKm(0), 0);
    });

    test('distance display and entry conversions are reversible', () {
      for (final kilometers in [0.0, 0.25, 5.0, 42.195]) {
        final displayed = settings.displayDistanceFromKm(kilometers);
        final restored = settings.enteredDistanceToKm(displayed);

        expect(restored, closeTo(kilometers, 0.0000001));
      }
    });

    test('converts km/h to mph and formats the result', () {
      expect(settings.displaySpeedFromKmh(10), closeTo(6.21371, 0.000001));
      expect(settings.formatSpeedFromKmh(10), '6.2 mph');
      expect(settings.formatSpeedFromKmh(10, decimals: 2), '6.21 mph');
      expect(settings.formatSpeedFromKmh(0), '0.0 mph');
    });

    test('converts meters to feet including negative elevations', () {
      expect(
        settings.displayElevationFromMeters(100),
        closeTo(328.084, 0.000001),
      );
      expect(settings.formatElevationFromMeters(100), '328 ft');
      expect(settings.formatElevationFromMeters(100, decimals: 1), '328.1 ft');
      expect(settings.formatElevationFromMeters(0), '0 ft');
      expect(settings.formatElevationFromMeters(-10), '-33 ft');
    });
  });

  group('Pace formatting', () {
    test('formats metric minutes and pads single-digit seconds', () {
      expect(settings.formatPaceFromSecondsPerKm(300), '5:00 /km');
      expect(settings.formatPaceFromSecondsPerKm(305), '5:05 /km');
      expect(settings.formatPaceFromSecondsPerKm(59), '0:59 /km');
    });

    test('rounds seconds correctly across a minute boundary', () {
      expect(settings.formatPaceFromSecondsPerKm(359.4), '5:59 /km');
      expect(settings.formatPaceFromSecondsPerKm(359.6), '6:00 /km');
    });

    test('converts seconds per kilometer into seconds per mile', () async {
      await settings.setMeasurementSystem(MeasurementSystem.imperial);

      expect(settings.formatPaceFromSecondsPerKm(300), '8:03 /mi');
      expect(settings.formatPaceFromSecondsPerKm(360), '9:39 /mi');
    });

    for (final system in MeasurementSystem.values) {
      test(
        'rejects zero, negative and non-finite pace in ${system.name}',
        () async {
          await settings.setMeasurementSystem(system);

          for (final invalid in [
            0.0,
            -1.0,
            double.nan,
            double.infinity,
            double.negativeInfinity,
          ]) {
            expect(
              settings.formatPaceFromSecondsPerKm(invalid),
              '—',
              reason: 'Invalid pace $invalid should not be displayed.',
            );
          }
        },
      );
    }
  });
}
