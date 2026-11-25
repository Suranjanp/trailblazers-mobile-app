import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/dashboard_calendar_cache.dart';
import '../theme/app_colors.dart';
import 'auth_screen.dart';
import 'profile_setup_screen.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key});

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late final FirebaseAuth _auth;
  late final Stream<User?> _authChanges;

  String? _profileUserId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileChanges;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance;
    _authChanges = _auth.userChanges();
  }

  void _message(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _resetPassword(User user) async {
    final email = user.email;

    if (_busy || email == null) {
      return;
    }

    final confirmed = await _confirm(
      'Reset password',
      'Send a password reset link to $email?',
      'Send link',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _busy = true);

    try {
      await _auth.sendPasswordResetEmail(email: email);

      _message('Reset link requested. Check your inbox and spam folder.');
    } on FirebaseAuthException catch (error) {
      _message(
        error.code == 'network-request-failed'
            ? 'Check your internet connection and try again.'
            : 'Could not send the reset link. Please try again.',
      );
    } catch (_) {
      _message('Could not send the reset link. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (_busy) {
      return;
    }

    final confirmed = await _confirm(
      'Sign out?',
      'Your account records will remain available when you log in again.',
      'Sign out',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _busy = true);

    try {
      await _auth.signOut();
      DashboardCalendarCache.instance.clear();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (_) {
      _message('Could not sign out. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openAuth(bool signUp) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => AuthScreen(signUp: signUp)),
    );

    if (mounted) {
      setState(() {});
    }
  }

  void _edit(User user, Map<String, dynamic> saved) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSetupScreen(
          userId: user.uid,
          initialName: user.displayName ?? '',
          savedProfile: saved,
          openedFromProfile: true,
        ),
      ),
    );
  }

  String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  double? _positive(dynamic value) {
    if (value is! num || !value.isFinite || value <= 0) {
      return null;
    }

    return value.toDouble();
  }

  String _weight(dynamic value) {
    final kg = _positive(value);

    if (kg == null) {
      return 'Not set';
    }

    return _formatWeight(kg);
  }

  String _formatWeight(double kg, {bool showSign = false}) {
    final metric = AppSettings.instance.isMetric;
    final converted = metric ? kg : kg * 2.2046226218;
    final rounded = double.parse(converted.toStringAsFixed(1));
    final normalized = rounded == 0 ? 0.0 : rounded;
    final prefix = showSign && normalized > 0 ? '+' : '';

    return '$prefix${normalized.toStringAsFixed(1)} '
        '${metric ? 'kg' : 'lb'}';
  }

  String _date(Timestamp timestamp) {
    final date = timestamp.toDate().toLocal();

    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.navigationNavy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.navigationNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guest() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _card('Your profile', Icons.person_outline, [
          Text(
            'Make Trailblazer yours',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Log in or create an account to manage your goals '
            'and saved profile.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _openAuth(false),
            icon: const Icon(Icons.login),
            label: const Text('Log in'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openAuth(true),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Create account'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Logging in opens that account’s records. Guest records '
            'are not automatically merged into an existing account.',
          ),
        ]),
      ],
    );
  }

  Widget _content(
    User user,
    Map<String, dynamic> saved, {
    required bool loading,
    String? error,
  }) {
    final theme = Theme.of(context);

    final name = _text(saved['name'], _text(user.displayName, 'Your profile'));

    final initials = name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((word) => word.substring(0, 1))
        .join()
        .toUpperCase();

    final goal = switch (saved['bodyGoal']) {
      'lose' => 'Lose weight',
      'gain' => 'Gain weight',
      'maintain' => 'Maintain weight',
      _ => 'Not set',
    };

    final activity = switch (saved['activityLevel']) {
      'inactive' => 'Inactive',
      'lowActive' => 'Low active',
      'active' => 'Active',
      'veryActive' => 'Very active',
      _ => 'Not set',
    };

    final calorieTarget = _positive(saved['calorieTarget']);
    final currentWeight = _positive(saved['weightKg']);
    final startingWeight = _positive(saved['startingWeightKg']);
    final targetWeight = _positive(saved['targetWeightKg']);
    final height = _positive(saved['heightCm']);
    final age = _positive(saved['ageYears']);

    final metric = AppSettings.instance.isMetric;
    final canEdit = !_busy && !loading && error == null;

    final history = <Map<String, dynamic>>[];
    final rawHistory = saved['weightHistory'];

    if (rawHistory is List) {
      for (final entry in rawHistory) {
        final weight = entry is Map ? _positive(entry['weightKg']) : null;

        if (entry is Map && weight != null && entry['loggedAt'] is Timestamp) {
          history.add({'weightKg': weight, 'loggedAt': entry['loggedAt']});
        }
      }
    }

    history.sort(
      (a, b) =>
          (b['loggedAt'] as Timestamp).compareTo(a['loggedAt'] as Timestamp),
    );

    final change = currentWeight != null && startingWeight != null
        ? currentWeight - startingWeight
        : null;

    final passwordAccount = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Your goals, your pace.',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _card('My profile', Icons.person_outline, [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFFEAF3F8),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppColors.navigationNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    if (user.email != null) ...[
                      const SizedBox(height: 4),
                      Text(user.email!),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: canEdit ? () => _edit(user, saved) : null,
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              currentWeight == null ? 'Set up profile' : 'Edit profile',
            ),
          ),
        ]),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          _card('Profile unavailable', Icons.info_outline, [
            Text(
              'Could not load your profile ($error). '
              'Check your connection and account permissions.',
            ),
          ]),
        if (!loading && error == null) ...[
          _card('My goal', Icons.flag_outlined, [
            Text(goal, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              calorieTarget == null
                  ? 'Calorie target not set'
                  : '${calorieTarget.toStringAsFixed(0)} kcal/day',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.trailblazerOrange,
                fontWeight: FontWeight.w700,
              ),
            ),
            _detail('Target weight', _weight(targetWeight)),
            _detail('Activity level', activity),
            const SizedBox(height: 8),
            const Text(
              'Nutrition uses your saved calorie target. '
              'Recalculate or enter a new target in Edit profile '
              'when your needs change.',
            ),
          ]),
          _card('Body details', Icons.accessibility_new_outlined, [
            _detail(
              'Age',
              age == null ? 'Not set' : '${age.toStringAsFixed(0)} years',
            ),
            _detail(
              'Height',
              height == null
                  ? 'Not set'
                  : '${(metric ? height : height / 2.54).toStringAsFixed(1)} '
                        '${metric ? 'cm' : 'in'}',
            ),
            _detail('Current weight', _weight(currentWeight)),
          ]),
          _card('Weight progress', Icons.show_chart, [
            _detail('Starting weight', _weight(startingWeight)),
            _detail('Current weight', _weight(currentWeight)),
            if (change != null)
              _detail(
                'Change since first check-in',
                _formatWeight(change, showSign: true),
              ),
            if (currentWeight != null && targetWeight != null)
              _detail(
                'Difference from target',
                _formatWeight((currentWeight - targetWeight).abs()),
              ),
            const SizedBox(height: 8),
            const Text(
              'Update your current weight in Edit profile to record '
              'a check-in. Saving unchanged weight does not add '
              'another entry.',
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const Text('No check-ins yet. Save your profile to begin.')
            else ...[
              Text('Recent check-ins', style: theme.textTheme.titleSmall),
              for (final entry in history.take(5))
                _detail(
                  _date(entry['loggedAt'] as Timestamp),
                  _weight(entry['weightKg']),
                ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: canEdit ? () => _edit(user, saved) : null,
              icon: const Icon(Icons.monitor_weight_outlined),
              label: const Text('Update weight'),
            ),
          ]),
        ],
        _card('Account & security', Icons.lock_outline, [
          if (passwordAccount)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _resetPassword(user),
              icon: const Icon(Icons.password_outlined),
              label: const Text('Reset password'),
            )
          else
            const Text('Manage your password through your sign-in provider.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: Text(_busy ? 'Please wait…' : 'Sign out'),
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authChanges,
      initialData: _auth.currentUser,
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;

        if (user == null || user.isAnonymous) {
          _profileUserId = null;
          _profileChanges = null;
          return _guest();
        }

        if (_profileUserId != user.uid) {
          _profileUserId = user.uid;
          _profileChanges = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(user.uid),
          stream: _profileChanges,
          builder: (context, snapshot) {
            final error = snapshot.error;

            final errorCode = snapshot.hasError
                ? error is FirebaseException
                      ? error.code
                      : 'unknown'
                : null;

            return AnimatedBuilder(
              animation: AppSettings.instance,
              builder: (context, _) => _content(
                user,
                snapshot.data?.data() ?? <String, dynamic>{},
                loading: !snapshot.hasData && !snapshot.hasError,
                error: errorCode,
              ),
            );
          },
        );
      },
    );
  }
}
