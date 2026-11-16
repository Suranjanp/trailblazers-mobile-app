import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_setup_screen.dart';

class AccountProfileScreen extends StatelessWidget {
  const AccountProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const Center(child: Text('Sign in to set up your profile.'));
    }

    final profile = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profile.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          final code = error is FirebaseException ? error.code : 'unknown';
          return Center(child: Text('Could not load your profile ($code).'));
        }

        final document = snapshot.data;
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final saved = document.data() ?? <String, dynamic>{};
        final name = saved['name'];
        final hasProfile =
            saved['ageYears'] is int &&
            saved['heightCm'] is num &&
            saved['weightKg'] is num &&
            saved['bodyGoal'] is String;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              name is String && name.trim().isNotEmpty ? name : 'Your profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (user.email != null) Text(user.email!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
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
              },
              child: Text(hasProfile ? 'Edit profile' : 'Set up profile'),
            ),
          ],
        );
      },
    );
  }
}
