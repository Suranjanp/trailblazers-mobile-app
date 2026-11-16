import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:test_ap_1/theme/app_colors.dart';

import 'account_profile_screen.dart';
import 'health_screen.dart';
import 'home_screen.dart';
import 'nutrition_screen.dart';
import 'schedule_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    this.profileScreen = const AccountProfileScreen(),
  });

  final Widget profileScreen;

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

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final currentDate = DateFormat('E, MMM d').format(DateTime.now());

    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: NavigationBarThemeData(
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
            (states) => states.contains(WidgetState.selected)
                ? const IconThemeData(color: AppColors.trailblazerOrange)
                : const IconThemeData(color: Colors.white),
          ),
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(color: Colors.white),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.navigationNavy,
          foregroundColor: Colors.white,
          title: Text(
            'Trailblazer · ${_titles[_selectedIndex]}',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  currentDate,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        drawer: NavigationDrawer(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            _selectDestination(index);
            Navigator.of(context).pop();
          },
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Trailblazer',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            for (var index = 0; index < _titles.length; index++)
              NavigationDrawerDestination(
                icon: Icon(_icons[index]),
                label: Text(_titles[index]),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (_selectedIndex) {
            0 => const HomeScreen(),
            1 => const ScheduleScreen(),
            2 => const NutritionScreen(),
            3 => const HealthScreen(),
            5 => widget.profileScreen,
            _ => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fitness_center,
                      size: 64,
                      color: AppColors.navigationNavy,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Fitness',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Record workouts, steps, and fitness goals.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          backgroundColor: AppColors.navigationNavy,
          indicatorColor: AppColors.actionBlue,
          onDestinationSelected: _selectDestination,
          destinations: [
            for (var index = 0; index < _titles.length; index++)
              NavigationDestination(
                icon: Icon(_icons[index]),
                label: _titles[index],
              ),
          ],
        ),
      ),
    );
  }
}