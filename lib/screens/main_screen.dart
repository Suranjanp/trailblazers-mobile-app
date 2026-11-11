
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:test_ap_1/theme/app_colors.dart';

import 'home_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const Color primaryNavy = Color(0xFF073B5B);
  static const Color backgroundGray = Color(0xFFF4F7F9);

  static const _titles = [
    'Dashboard',
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
    final currentDate = DateFormat('E, MMM d').format(DateTime.now());

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: backgroundGray,

        // Navigation bar icon colors
        navigationBarTheme: NavigationBarThemeData(
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: AppColors.trailblazerOrange);
              }
              return const IconThemeData(color: Colors.white);
            },
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: primaryNavy,
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),

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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
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
          child: _selectedIndex == 0
              ? const HomeScreen()
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _icons[_selectedIndex],
                          size: 64,
                          color: primaryNavy,
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

        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          backgroundColor: AppColors.navigationNavy,
          indicatorColor: AppColors.actionBlue,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
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
