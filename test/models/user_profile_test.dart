import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/models/user_profile.dart';

void main() {
  // Checks every field so a missing or incorrectly copied field is detected.
  void expectProfile(
    UserProfile actual,
    UserProfile expected,
  ) {
    expect(actual.name, expected.name);
    expect(actual.calorieTarget, expected.calorieTarget);
    expect(actual.proteinTargetGrams, expected.proteinTargetGrams);
    expect(actual.waterTargetMl, expected.waterTargetMl);
    expect(actual.sleepTargetHours, expected.sleepTargetHours);
    expect(actual.stepTarget, expected.stepTarget);
  }

  const customProfile = UserProfile(
    name: 'Suranjan',
    calorieTarget: 2300,
    proteinTargetGrams: 125,
    waterTargetMl: 2500,
    sleepTargetHours: 7.5,
    stepTarget: 10000,
  );

  group('UserProfile constructor', () {
    test('uses the documented starter values', () {
      const profile = UserProfile();

      expect(profile.name, '');
      expect(profile.calorieTarget, 2000);
      expect(profile.proteinTargetGrams, 100);
      expect(profile.waterTargetMl, 2000);
      expect(profile.sleepTargetHours, 8.0);
      expect(profile.stepTarget, 8000);
    });

    test('stores all supplied values', () {
      expect(customProfile.name, 'Suranjan');
      expect(customProfile.calorieTarget, 2300);
      expect(customProfile.proteinTargetGrams, 125);
      expect(customProfile.waterTargetMl, 2500);
      expect(customProfile.sleepTargetHours, 7.5);
      expect(customProfile.stepTarget, 10000);
    });
  });

  group('UserProfile.copyWith', () {
    test('preserves every field when no changes are supplied', () {
      final copy = customProfile.copyWith();

      expectProfile(copy, customProfile);
      expect(identical(copy, customProfile), isFalse);
    });

    test('updates every field when all changes are supplied', () {
      final updated = customProfile.copyWith(
        name: 'Updated name',
        calorieTarget: 2400,
        proteinTargetGrams: 140,
        waterTargetMl: 3000,
        sleepTargetHours: 8.5,
        stepTarget: 12000,
      );

      expectProfile(
        updated,
        const UserProfile(
          name: 'Updated name',
          calorieTarget: 2400,
          proteinTargetGrams: 140,
          waterTargetMl: 3000,
          sleepTargetHours: 8.5,
          stepTarget: 12000,
        ),
      );

      // Updating a copy must not modify the original.
      expect(customProfile.name, 'Suranjan');
      expect(customProfile.calorieTarget, 2300);
      expect(customProfile.proteinTargetGrams, 125);
      expect(customProfile.waterTargetMl, 2500);
      expect(customProfile.sleepTargetHours, 7.5);
      expect(customProfile.stepTarget, 10000);
    });

    test('updates one field while preserving all other fields', () {
      final updated = customProfile.copyWith(calorieTarget: 2600);

      expectProfile(
        updated,
        const UserProfile(
          name: 'Suranjan',
          calorieTarget: 2600,
          proteinTargetGrams: 125,
          waterTargetMl: 2500,
          sleepTargetHours: 7.5,
          stepTarget: 10000,
        ),
      );
    });

    test('treats explicit null arguments as unchanged fields', () {
      final updated = customProfile.copyWith(
        name: null,
        calorieTarget: null,
        proteinTargetGrams: null,
        waterTargetMl: null,
        sleepTargetHours: null,
        stepTarget: null,
      );

      expectProfile(updated, customProfile);
    });

    test('accepts empty names and zero values without using defaults', () {
      final updated = customProfile.copyWith(
        name: '',
        calorieTarget: 0,
        proteinTargetGrams: 0,
        waterTargetMl: 0,
        sleepTargetHours: 0.0,
        stepTarget: 0,
      );

      expectProfile(
        updated,
        const UserProfile(
          name: '',
          calorieTarget: 0,
          proteinTargetGrams: 0,
          waterTargetMl: 0,
          sleepTargetHours: 0.0,
          stepTarget: 0,
        ),
      );
    });
  });

  group('UserProfile.toJson', () {
    test('exports the exact storage keys and values', () {
      expect(customProfile.toJson(), {
        'name': 'Suranjan',
        'calorieTarget': 2300,
        'proteinTargetGrams': 125,
        'waterTargetMl': 2500,
        'sleepTargetHours': 7.5,
        'stepTarget': 10000,
      });
    });

    test('changing the exported map does not change the profile', () {
      final json = customProfile.toJson();
      json['name'] = 'Changed externally';
      json['calorieTarget'] = 999;

      expect(customProfile.name, 'Suranjan');
      expect(customProfile.calorieTarget, 2300);
    });
  });

  group('UserProfile.fromJson', () {
    test('restores all fields from saved data', () {
      final profile = UserProfile.fromJson({
        'name': 'Suranjan',
        'calorieTarget': 2300,
        'proteinTargetGrams': 125,
        'waterTargetMl': 2500,
        'sleepTargetHours': 7.5,
        'stepTarget': 10000,
      });

      expectProfile(profile, customProfile);
    });

    test('uses defaults when all fields are missing', () {
      final profile = UserProfile.fromJson({});

      expectProfile(profile, const UserProfile());
    });

    test('uses defaults when saved fields are null', () {
      final profile = UserProfile.fromJson({
        'name': null,
        'calorieTarget': null,
        'proteinTargetGrams': null,
        'waterTargetMl': null,
        'sleepTargetHours': null,
        'stepTarget': null,
      });

      expectProfile(profile, const UserProfile());
    });

    test('loads older records with only some fields present', () {
      final profile = UserProfile.fromJson({
        'name': 'Older account',
        'calorieTarget': 2200,
      });

      expectProfile(
        profile,
        const UserProfile(
          name: 'Older account',
          calorieTarget: 2200,
        ),
      );
    });

    test('converts double values into integer target fields', () {
      final profile = UserProfile.fromJson({
        'calorieTarget': 2300.9,
        'proteinTargetGrams': 125.8,
        'waterTargetMl': 2500.7,
        'stepTarget': 10000.6,
      });

      // The current model uses toInt(), which truncates decimals.
      expect(profile.calorieTarget, 2300);
      expect(profile.proteinTargetGrams, 125);
      expect(profile.waterTargetMl, 2500);
      expect(profile.stepTarget, 10000);
    });

    test('converts an integer sleep target into a double', () {
      final profile = UserProfile.fromJson({
        'sleepTargetHours': 9,
      });

      expect(profile.sleepTargetHours, 9.0);
      expect(profile.sleepTargetHours, isA<double>());
    });

    test('preserves explicit zero values', () {
      final profile = UserProfile.fromJson({
        'name': '',
        'calorieTarget': 0,
        'proteinTargetGrams': 0,
        'waterTargetMl': 0,
        'sleepTargetHours': 0,
        'stepTarget': 0,
      });

      expectProfile(
        profile,
        const UserProfile(
          calorieTarget: 0,
          proteinTargetGrams: 0,
          waterTargetMl: 0,
          sleepTargetHours: 0.0,
          stepTarget: 0,
        ),
      );
    });

    test('ignores unknown fields without modifying the input map', () {
      final saved = <String, dynamic>{
        'name': 'Suranjan',
        'futureSetting': true,
      };
      final original = Map<String, dynamic>.from(saved);

      final profile = UserProfile.fromJson(saved);

      expectProfile(profile, const UserProfile(name: 'Suranjan'));
      expect(saved, original);
    });

    final invalidFields = <String, dynamic>{
      'name': 42,
      'calorieTarget': '2000',
      'proteinTargetGrams': '100',
      'waterTargetMl': '2000',
      'sleepTargetHours': '8',
      'stepTarget': '8000',
    };

    for (final entry in invalidFields.entries) {
      test('rejects an incorrect type for ${entry.key}', () {
        expect(
          () => UserProfile.fromJson({entry.key: entry.value}),
          throwsA(isA<TypeError>()),
        );
      });
    }
  });

  group('UserProfile JSON round trip', () {
    test('all fields survive JSON encoding and decoding', () {
      final encoded = jsonEncode(customProfile.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored = UserProfile.fromJson(decoded);

      expectProfile(restored, customProfile);
    });

    test('preserves Unicode names and special characters', () {
      const original = UserProfile(
        name: 'सुरञ्जन "Trailblazer" 🏃',
        sleepTargetHours: 7.25,
      );

      final encoded = jsonEncode(original.toJson());
      final restored = UserProfile.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expectProfile(restored, original);
    });
  });
}