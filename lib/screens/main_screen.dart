import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Change these for a default class theme
  static const Color primaryNavy = Color(0xFF073B5B);
  static const Color backgroundGray = Color(0xFFF4F7F9);
  static const Color accentOrange = Color(0xFFF15A24);
  static const Color textDark = Color(0xFF0F2537);
  static const Color textMuted = Color(0xFF6B7C93);

  static const _titles = [
    'Home',
    'Schedule',
    'Metrics',
    'Profile',
  ];

  static const _icons = [
    Icons.home_outlined,
    Icons.calendar_today_outlined,
    Icons.timeline_outlined, // Styled closely to the zigzag metrics icon
    Icons.person_outline,
  ];

  static const _descriptions = [
    'Your schedule and wellness progress will appear here.',
    'Manage your classes and weekly schedule.',
    'Record meals, workouts, water intake, and fitness goals.',
    'Manage your personal information and daily targets.',
  ];

  @override
  Widget build(BuildContext context) {
    final currentDateStr = DateFormat('E, MMM d').format(DateTime.now());

    return Theme(
      // Applies the design's specific color palette to this screen
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: backgroundGray,
      ),
      child: Scaffold(
        body: Column(
          children: [
            // Custom Deep Navy Header mimicking the app's top bar
            Container(
              color: primaryNavy,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Orange App Logo Badge
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentOrange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'T',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // App Name
                      const Text(
                        'Trailblazer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    currentDateStr,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // Main Content Area
            Expanded(
              child: SafeArea(
                top: false, // Prevents safe area padding conflict with our custom header
                child: Center(
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
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _descriptions[_selectedIndex],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: textMuted,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Clean Bottom Navigation Bar styled to match the image layout
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: primaryNavy,
            unselectedItemColor: textMuted,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            elevation: 0,
            items: List.generate(_titles.length, (index) {
              return BottomNavigationBarItem(
                icon: Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Icon(_icons[index]),
                ),
                label: _titles[index],
              );
            }),
          ),
        ),
      ),
    );
  }
}
