// Stores one user's name and daily targets.
// Units are included in field names to avoid confusion across the team.
class UserProfile {
  final String name;
  final int calorieTarget;
  final int proteinTargetGrams;
  final int waterTargetMl;
  final double sleepTargetHours;
  final int stepTarget;

  // These are starter values users can edit, not calculated recommendations.
  const UserProfile({
    this.name = '',
    this.calorieTarget = 2000,
    this.proteinTargetGrams = 100,
    this.waterTargetMl = 2000,
    this.sleepTargetHours = 8,
    this.stepTarget = 8000,
  });

  // Creates an updated profile while keeping fields that were not supplied.
  // The original object stays unchanged because its fields are final.
  UserProfile copyWith({
    String? name,
    int? calorieTarget,
    int? proteinTargetGrams,
    int? waterTargetMl,
    double? sleepTargetHours,
    int? stepTarget,
  }) {
    return UserProfile(
      name: name ?? this.name,
      calorieTarget: calorieTarget ?? this.calorieTarget,
      proteinTargetGrams: proteinTargetGrams ?? this.proteinTargetGrams,
      waterTargetMl: waterTargetMl ?? this.waterTargetMl,
      sleepTargetHours: sleepTargetHours ?? this.sleepTargetHours,
      stepTarget: stepTarget ?? this.stepTarget,
    );
  }

  // Converts the profile into values we can later encode as JSON and save.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'calorieTarget': calorieTarget,
      'proteinTargetGrams': proteinTargetGrams,
      'waterTargetMl': waterTargetMl,
      'sleepTargetHours': sleepTargetHours,
      'stepTarget': stepTarget,
    };
  }

  // Rebuilds a profile from saved data.
  // Missing fields use defaults so older records can still be loaded
  // when new fields are added to the app.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      calorieTarget: (json['calorieTarget'] as num?)?.toInt() ?? 2000,
      proteinTargetGrams: (json['proteinTargetGrams'] as num?)?.toInt() ?? 100,
      waterTargetMl: (json['waterTargetMl'] as num?)?.toInt() ?? 2000,
      sleepTargetHours: (json['sleepTargetHours'] as num?)?.toDouble() ?? 8,
      stepTarget: (json['stepTarget'] as num?)?.toInt() ?? 8000,
    );
  }
}
