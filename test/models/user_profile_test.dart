import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_ap_1/models/user_profile.dart';

void main() {
  group('UserProfile', () {
    test('all profile fields survive JSON encoding and decoding', () {
      const original = UserProfile(
        name: 'Suranjan',
        calorieTarget: 2300,
        proteinTargetGrams: 120,
        waterTargetMl: 2500,
        sleepTargetHours: 7.5,
        stepTarget: 9000,
      );

      // Simulates converting a profile to saved text and loading it again.
      final encoded = jsonEncode(original.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored = UserProfile.fromJson(decoded);

      expect(restored.toJson(), equals(original.toJson()));
    });

    test('updating a field preserves other values and the original', () {
      const original = UserProfile(name: 'Suranjan', waterTargetMl: 2500);

      final updated = original.copyWith(name: 'Sam');

      expect(updated.name, 'Sam');
      expect(updated.waterTargetMl, 2500);
      expect(original.name, 'Suranjan');
    });

    test('missing saved fields fall back to defaults', () {
      final profile = UserProfile.fromJson({'name': 'Suranjan'});

      expect(profile.name, 'Suranjan');
      expect(profile.calorieTarget, 2000);
      expect(profile.waterTargetMl, 2000);
      expect(profile.sleepTargetHours, 8);
    });

    test('sleep hours accept whole numbers from saved JSON', () {
      final profile = UserProfile.fromJson({'sleepTargetHours': 7});

      expect(profile.sleepTargetHours, 7.0);
    });
  });
}
