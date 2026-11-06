import 'package:flutter/material.dart';
import 'home_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const orange = Color(0xFFF15A24);
    const softOrange = Color(0xFFFFF0E9);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'YOUR DAY, YOUR PACE',
          style: text.labelLarge?.copyWith(
            color: const Color(0xFFB23D13),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text('Welcome to Trailblazer', style: text.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          "A little movement goes a long way. Here's your day at a glance.",
        ),
        const SizedBox(height: 8),
        Text('Made by students for students', style: text.labelLarge),
        const SizedBox(height: 20),

        Card(
          color: softOrange,
          child: ListTile(
            leading: const Icon(Icons.star_rounded, color: orange),
            title: const Text('Trail Points'),
            subtitle: const Text('Earn 25 points for each completed goal.'),
          ),
        ),
        const SizedBox(height: 12),

        // Each card expands in place, like the sections in the HTML prototype.
        const _HomeCard(
          icon: Icons.calendar_month_outlined,
          title: 'Schedule',
          subtitle: "Today's classes and workouts",
          details: 'Classes and workouts will appear here.',
        ),
        const _HomeCard(
          icon: Icons.flag_outlined,
          title: 'Goals',
          subtitle: 'Weekly progress',
          details: 'Weekly progress for steps, calories burned, and water.',
        ),
        const _HomeCard(
          icon: Icons.bar_chart_outlined,
          title: 'Metrics',
          subtitle: 'Daily progress toward each goal',
          details: 'Daily totals for steps, calories burned, and water.',
        ),
        const SizedBox(height: 8),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move well, study well, play well, eat well, rest well.',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('A Trailblazer reminder'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.details,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        expandedAlignment: Alignment.centerLeft,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [Text(details)],
      ),
    );
  }
}
