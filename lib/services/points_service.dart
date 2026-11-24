import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The kinds of accomplishments that can earn Trailblazer Points.
///
/// The enum names are also persisted as transaction category values, so keep
/// them stable unless the corresponding stored data and report handling are
/// migrated together.
enum PointsActivityType {
  todo,
  workout,
  healthGoal,
  scheduleCommitment,
  dailyGoals,
}

/// Result returned when an activity is submitted for points.
///
/// [awarded] distinguishes a new award from a duplicate submission.
/// [points] is zero for a duplicate, while [totalPoints] always reflects the
/// user's balance read during the Firestore transaction.
class PointsAwardResult {
  const PointsAwardResult({
    required this.awarded,
    required this.points,
    required this.totalPoints,
  });

  /// False when this exact activity was already rewarded.
  final bool awarded;
  final int points;
  final int totalPoints;
}

/// A time-bounded summary of points and the activities that earned them.
///
/// [pointsByCategory] stores category totals using the persisted activity
/// type names as keys; [pointsFor] safely returns zero for an absent category.
class PointsReport {
  const PointsReport({
    required this.start,
    required this.end,
    required this.totalPoints,
    required this.activityCount,
    required this.pointsByCategory,
  });

  final DateTime start;
  final DateTime end;
  final int totalPoints;
  final int activityCount;
  final Map<String, int> pointsByCategory;

  int pointsFor(String category) => pointsByCategory[category] ?? 0;
}

/// Centralized Trailblazer scoring and points history.
///
/// Records are stored under:
/// users/{uid}/points_transactions/{activityKey}
///
/// The deterministic activity key and Firestore transaction make awarding
/// points idempotent: completing or saving the same activity more than once
/// cannot award duplicate points.
///
/// Screens should submit completed activities through this service instead
/// of updating balances or writing transaction documents directly.
class PointsService {
  PointsService._();

  static final PointsService instance = PointsService._();

  // Reward values are centralized here so every feature uses the same scoring
  // rules and changes to the points economy can be made in one location.
  static const int todoImportanceOnePoints = 10;
  static const int todoImportanceTwoPoints = 15;
  static const int todoImportanceThreePoints = 25;
  static const int todoImportanceFourPoints = 40;
  static const int todoImportanceFivePoints = 50;
  static const int workoutPoints = 40;
  static const int healthGoalPoints = 20;
  static const int scheduleCommitmentPoints = 25;
  static const int dailyGoalsPoints = 30;

  // Resolve Firebase instances when needed so the service always uses the
  // application's configured Firestore database and current auth session.
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  User? get _user => FirebaseAuth.instance.currentUser;

  /// Returns the user's aggregate points profile document reference.
  ///
  /// The profile stores the lifetime balance and timestamps, separate from
  /// the individual transaction history.
  DocumentReference<Map<String, dynamic>> _profileDocument(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('points')
        .doc('profile');
  }

  /// Returns the collection containing the user's immutable award records.
  CollectionReference<Map<String, dynamic>> _transactions(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('points_transactions');
  }

  /// Returns the configured reward for an activity.
  ///
  /// To-do importance is clamped to the supported 1–5 range so unexpected
  /// caller values cannot select an undefined reward tier.
  int pointsForActivity(PointsActivityType type, {int importance = 1}) {
    switch (type) {
      case PointsActivityType.todo:
        switch (importance.clamp(1, 5)) {
          case 1:
            return todoImportanceOnePoints;
          case 2:
            return todoImportanceTwoPoints;
          case 3:
            return todoImportanceThreePoints;
          case 4:
            return todoImportanceFourPoints;
          default:
            return todoImportanceFivePoints;
        }
      case PointsActivityType.workout:
        return workoutPoints;
      case PointsActivityType.healthGoal:
        return healthGoalPoints;
      case PointsActivityType.scheduleCommitment:
        return scheduleCommitmentPoints;
      case PointsActivityType.dailyGoals:
        return dailyGoalsPoints;
    }
  }

  /// Awards points once for a completed activity.
  ///
  /// [sourceId] must be a stable ID for the completed item or workout. Do not
  /// use a list index, current timestamp, or Dart's hashCode as the ID.
  ///
  /// Returns null when no user is signed in. Throws if Firestore cannot save
  /// the award so the calling screen can show an appropriate error.
  Future<PointsAwardResult?> awardActivity({
    required PointsActivityType type,
    required String sourceId,
    required String title,
    int importance = 1,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    // Points are scoped to the authenticated account; guests or signed-out
    // users do not receive a persisted award.
    final user = _user;
    if (user == null) return null;

    // Normalize the caller's stable ID before deriving the transaction
    // document key, and reject empty IDs that could collide unintentionally.
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'Must not be empty.');
    }

    final points = pointsForActivity(type, importance: importance);
    final activityKey = activityDocumentId(type, normalizedSourceId);

    // Both the transaction record and aggregate profile are updated atomically
    // so the history and lifetime balance cannot drift apart on a partial write.
    final transactionRef = _transactions(user.uid).doc(activityKey);
    final profileRef = _profileDocument(user.uid);
    final earnedAt = DateTime.now();

    return _firestore.runTransaction<PointsAwardResult>((transaction) async {
      // Read both documents before writing. Firestore can retry this callback
      // if concurrent activity submissions modify either document.
      final existingAward = await transaction.get(transactionRef);
      final profileSnapshot = await transaction.get(profileRef);
      final profile = profileSnapshot.data() ?? <String, dynamic>{};
      final currentTotal = (profile['totalPoints'] as num?)?.toInt() ?? 0;

      // An existing deterministic transaction means this exact activity has
      // already been rewarded. Return the current balance without writing.
      if (existingAward.exists) {
        return PointsAwardResult(
          awarded: false,
          points: 0,
          totalPoints: currentTotal,
        );
      }

      // Store the detailed activity record for history and period reports.
      // Metadata can hold feature-specific context without changing the schema.
      transaction.set(transactionRef, <String, dynamic>{
        'activityKey': activityKey,
        'activityType': type.name,
        'sourceId': normalizedSourceId,
        'title': title.trim().isEmpty ? 'Completed activity' : title.trim(),
        'points': points,
        'importance': type == PointsActivityType.todo
            ? importance.clamp(1, 5)
            : null,
        'metadata': metadata,
        'earnedAt': Timestamp.fromDate(earnedAt),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Merge the updated aggregate balance into the profile so unrelated
      // profile fields are preserved if this document already exists.
      transaction.set(profileRef, <String, dynamic>{
        'totalPoints': currentTotal + points,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastEarnedAt': Timestamp.fromDate(earnedAt),
      }, SetOptions(merge: true));

      return PointsAwardResult(
        awarded: true,
        points: points,
        totalPoints: currentTotal + points,
      );
    });
  }

  /// Reads the user's lifetime points balance.
  ///
  /// A signed-out session has no user-specific balance and therefore returns 0.
  Future<int> getTotalPoints() async {
    final user = _user;
    if (user == null) return 0;

    final snapshot = await _profileDocument(user.uid).get();
    return (snapshot.data()?['totalPoints'] as num?)?.toInt() ?? 0;
  }

  /// Builds a report for the supplied local date range.
  ///
  /// The end is exclusive. For example, a daily report should pass midnight
  /// today as [start] and midnight tomorrow as [end].
  Future<PointsReport> getReport({
    required DateTime start,
    required DateTime end,
  }) async {
    // Reject invalid or empty ranges rather than returning a misleading report.
    if (!end.isAfter(start)) {
      throw ArgumentError('The report end must be after its start.');
    }

    final user = _user;
    if (user == null) {
      // Return a correctly shaped empty report when there is no active account.
      return PointsReport(
        start: start,
        end: end,
        totalPoints: 0,
        activityCount: 0,
        pointsByCategory: const <String, int>{},
      );
    }

    // Query by earnedAt using an inclusive start and exclusive end. This
    // prevents an activity at the next period's midnight being counted twice.
    final snapshot = await _transactions(user.uid)
        .where('earnedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('earnedAt', isLessThan: Timestamp.fromDate(end))
        .get();

    var total = 0;
    final byCategory = <String, int>{};

    // Aggregate the transaction records locally into a total and category
    // breakdown for the requested reporting period.
    for (final document in snapshot.docs) {
      final data = document.data();
      final points = (data['points'] as num?)?.toInt() ?? 0;
      final category = data['activityType']?.toString() ?? 'other';
      total += points;
      byCategory[category] = (byCategory[category] ?? 0) + points;
    }

    return PointsReport(
      start: start,
      end: end,
      totalPoints: total,
      activityCount: snapshot.docs.length,
      pointsByCategory: byCategory,
    );
  }

  /// Daily report for the current local calendar day.
  ///
  /// The interval runs from local midnight to the next local midnight.
  Future<PointsReport> getDailyReport({DateTime? date}) {
    final day = date ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day);
    return getReport(start: start, end: start.add(const Duration(days: 1)));
  }

  /// Weekly report, Monday through Sunday, for the supplied local date.
  ///
  /// The date is normalized to its week's Monday before requesting a seven-day
  /// half-open report interval.
  Future<PointsReport> getWeeklyReport({DateTime? date}) {
    final day = date ?? DateTime.now();
    final today = DateTime(day.year, day.month, day.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    return getReport(start: start, end: start.add(const Duration(days: 7)));
  }

  /// Monthly report for the supplied local date.
  ///
  /// The end boundary is calculated as the first day of the following month,
  /// including the year transition from December to January.
  Future<PointsReport> getMonthlyReport({DateTime? date}) {
    final day = date ?? DateTime.now();
    final start = DateTime(day.year, day.month, 1);
    final end = day.month == 12
        ? DateTime(day.year + 1, 1, 1)
        : DateTime(day.year, day.month + 1, 1);
    return getReport(start: start, end: end);
  }

  /// Converts an activity type into a readable label for reports.
  String categoryLabel(String category) {
    switch (category) {
      case 'todo':
        return 'To-do tasks';
      case 'workout':
        return 'Workouts';
      case 'healthGoal':
        return 'Health goals';
      case 'scheduleCommitment':
        return 'Schedule commitments';
      case 'dailyGoals':
        return 'Daily goals';
      default:
        return 'Other activities';
    }
  }

  /// Creates a deterministic, Firestore-safe document ID for an activity.
  ///
  /// Base64 URL encoding preserves the source ID without introducing characters
  /// that are awkward in document paths. Removing padding keeps the key compact.
  /// The activity type is included so equal source IDs from different feature
  /// categories remain distinct.
  @visibleForTesting
  String activityDocumentId(PointsActivityType type, String sourceId) {
    final encodedId = base64Url
        .encode(utf8.encode(sourceId.trim()))
        .replaceAll('=', '');
    return '${type.name}_$encodedId';
  }
}
