import 'package:flutter/material.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _titles = [
    'Home',
    'Schedule',
    'Nutrition',
    'Health',
    'Fitness',
    'Profile',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.restaurant_outlined,
    Icons.favorite_outline,
    Icons.fitness_center,
    Icons.person_outline,
  ];

  static const _descriptions = [
    'Your schedule and wellness progress will appear here.',
    'Manage your classes and weekly schedule.',
    'Record meals, calories, and protein.',
    'Track your water intake and sleep.',
    'Record workouts, steps, and fitness goals.',
    'Manage your personal information and daily targets.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trailblazer · ${_titles[_selectedIndex]}')),
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });

          Navigator.pop(context);
        },
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Trailblazer',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          for (int i = 0; i < _titles.length; i++)
            NavigationDrawerDestination(
              icon: Icon(_icons[i]),
              label: Text(_titles[i]),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _icons[_selectedIndex],
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _titles[_selectedIndex],
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _descriptions[_selectedIndex],
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
