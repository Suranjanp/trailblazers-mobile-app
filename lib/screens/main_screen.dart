import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/dashboard_calendar_cache.dart';
import '../services/notification_settings.dart';
import '../theme/app_colors.dart';
import 'account_profile_screen.dart';
import 'auth_screen.dart';
import 'health_screen.dart';
import 'home_screen.dart';
import 'nutrition_screen.dart';
import 'schedule_screen.dart';
import 'fitness_screen.dart';

/// The main application shell that hosts each primary Trailblazer section.
///
/// A [PageView] keeps the selected section alive while allowing users to move
/// between destinations with either horizontal swipes or the bottom bar.
/// The profile widget is injectable so the shell can be reused with a custom
/// profile implementation when needed.
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
  // Controls page navigation and is disposed with this screen.
  final PageController _pageController = PageController();

  // Used to randomize inspirational quotes without immediately repeating one.
  final Random _random = Random();

  int _currentPageIndex = 0;

  // Keep destination titles and icons in the same order as the PageView pages.
  static const List<String> _titles = [
    'Home',
    'Schedule',
    'Nutrition',
    'Health',
    'Fitness',
    'Profile',
  ];

  // The profile destination is opened from the settings drawer rather than
  // being included in the bottom navigation bar.
  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.restaurant_outlined,
    Icons.favorite_outline,
    Icons.fitness_center,
  ];

  // Quote pool displayed when the user taps the Trailblazer logo in the app bar.
  static const List<String> _quotes = [
    'Small steps every day lead to extraordinary destinations.',
    'You do not have to be perfect. You just have to keep showing up.',
    'Discipline is choosing what you want most over what you want now.',
    'Your only competition is the person you were yesterday.',
    'Progress is built in the moments when quitting seems easier.',
    'The strongest version of yourself is built one decision at a time.',
    'A journey of a thousand miles begins with a single step.',
    'Consistency turns ordinary effort into extraordinary results.',
    'Do something today that your future self will thank you for.',
    'You are capable of more than your doubts would have you believe.',
    'Strength is not just what you can lift. It is what you can overcome.',
    'Every workout, every healthy choice, every small victory matters.',
    'Do not measure your progress against someone else’s timeline.',
    'Fall seven times, stand up eight.',
    'The hardest part is often simply beginning.',
    'Dream big. Start small. Keep moving forward.',
    'Your habits shape your future. Make them count.',
    'You cannot change yesterday, but you can influence tomorrow.',
    'Great things happen when preparation meets determination.',
    'Even slow progress is progress. Keep going.',
    'Your limits are often just the beginning of your potential.',
    'A stronger mind builds a stronger body.',
    'Do not wait for motivation. Build the discipline to begin.',
    'Every day is another opportunity to become a better version of yourself.',
    'Challenges are not roadblocks. They are opportunities to grow.',
    'The difference between where you are and where you want to be is what you do consistently.',
    'Believe in the work, even when you cannot see the results.',
    'One bad day does not erase all the good days.',
    'Be proud of how far you have come, and excited about where you are going.',
    'Your future is created by what you do today, not tomorrow.',
    'Strength grows through resistance. Character grows through challenges.',
    'Make progress your priority, not perfection.',
    'You are one decision away from a different direction.',
    'The goal is not to be better than everyone else. It is to be better than you were.',
    'Show up for yourself, especially on the days you do not feel like it.',
    'Great journeys are made of small victories.',
    'Your effort today is an investment in your tomorrow.',
    'Do not count the days. Make the days count.',
    'When things get difficult, remember why you started.',
    'The best time to improve yourself is always now.',
  ];

  // A shuffled deck avoids selecting the same quote repeatedly until the pool
  // has been used. _lastQuote is also checked when a new deck is created.
  late List<String> _quoteDeck;
  String? _lastQuote;

  @override
  void initState() {
    super.initState();
    _shuffleQuotes();

    // Load the device's saved notification preferences when the app shell opens.
    NotificationSettings.instance.load();
  }

  /// Rebuilds the quote deck and prevents its first item from matching the
  /// final quote shown from the previous deck.
  void _shuffleQuotes() {
    _quoteDeck = List<String>.from(_quotes)..shuffle(_random);

    if (_lastQuote != null &&
        _quoteDeck.length > 1 &&
        _quoteDeck.first == _lastQuote) {
      final replacementIndex = _random.nextInt(_quoteDeck.length - 1) + 1;
      final firstQuote = _quoteDeck.first;
      _quoteDeck[0] = _quoteDeck[replacementIndex];
      _quoteDeck[replacementIndex] = firstQuote;
    }
  }

  /// Returns the next quote, refreshing the shuffled deck when it is empty.
  String _getRandomQuote() {
    if (_quoteDeck.isEmpty) {
      _shuffleQuotes();
    }

    final quote = _quoteDeck.removeAt(0);
    _lastQuote = quote;
    return quote;
  }

  /// Opens the inspiration dialog. The dialog can be dismissed or replaced
  /// with another quote without leaving the current app section.
  void _showInspirationalQuote() {
    final quote = _getRandomQuote();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.navigationNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppColors.trailblazerOrange,
                size: 38,
              ),
              const SizedBox(height: 20),
              const Text(
                'A MOMENT OF INSPIRATION',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.trailblazerOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '“$quote”',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.trailblazerOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Keep Moving Forward',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _showInspirationalQuote();
                },
                child: const Text(
                  'Another Quote',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Animates to a primary destination selected in the bottom navigation bar.
  void _selectDestination(int index) {
    if (index < 0 || index >= _icons.length) return;

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  /// Keeps the app-bar title and selected navigation item synchronized with
  /// swipes and programmatic page changes.
  void _onPageChanged(int index) {
    setState(() => _currentPageIndex = index);
  }

  /// Closes the end drawer before navigating directly to the profile page.
  void _openProfileFromDrawer() {
    Navigator.of(context).pop();
    _pageController.animateToPage(
      5,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  /// Confirms sign-out, clears cached calendar data, and returns the user to
  /// authentication. Firebase errors are reported with a brief snackbar.
  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (shouldSignOut != true || !mounted) return;

    try {
      await FirebaseAuth.instance.signOut();
      DashboardCalendarCache.instance.clear();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed (${error.code}).')),
      );
    }
  }

  /// Builds the five primary destinations. Profile remains accessible from
  /// the quick-settings drawer to preserve the existing navigation layout.
  Widget _buildBottomNavigationBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: AppColors.navigationNavy,
        child: SizedBox(
          height: 66,
          child: Row(
            children: List.generate(_icons.length, (index) {
              final selected = _currentPageIndex == index;

              return Expanded(
                child: InkWell(
                  onTap: () => _selectDestination(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.actionBlue
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            _icons[index],
                            color: selected
                                ? AppColors.trailblazerOrange
                                : Colors.white,
                            size: 23,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _titles[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Release the controller when the navigation shell is removed.
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The app bar remains consistent across sections; its title reflects the
      // currently visible page and its logo opens the inspiration dialog.
      appBar: AppBar(
        backgroundColor: AppColors.navigationNavy,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Tooltip(
              message: 'Get inspired',
              child: InkWell(
                onTap: _showInspirationalQuote,
                borderRadius: BorderRadius.circular(30),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Image.asset(
                    'assets/images/top_icon.png',
                    width: 38,
                    height: 38,
                    fit: BoxFit.contain,
                    // Show a themed fallback if the image asset is unavailable.
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.explore,
                        size: 36,
                        color: AppColors.trailblazerOrange,
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trailblazer · ${_titles[_currentPageIndex]}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Builder supplies a context below the Scaffold so openEndDrawer()
          // targets this Scaffold rather than an ancestor.
          Builder(
            builder: (appBarContext) => IconButton(
              tooltip: 'Quick settings',
              icon: const Icon(Icons.settings_outlined),
              iconSize: 27,
              onPressed: () => Scaffold.of(appBarContext).openEndDrawer(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: _QuickSettingsDrawer(
        onOpenProfile: _openProfileFromDrawer,
        onSignOut: _signOut,
      ),
      // Each destination is a page in one PageView. PageStorageKeys help retain
      // page-specific scroll/state information when users switch sections.
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const PageScrollPhysics(),
          onPageChanged: _onPageChanged,
          children: [
            HomeScreen(
              key: const PageStorageKey('home'),
              onOpenSchedule: () => _selectDestination(1),
            ),
            const ScheduleScreen(key: PageStorageKey('schedule')),
            const NutritionScreen(key: PageStorageKey('nutrition')),
            const HealthScreen(key: PageStorageKey('health')),
            const FitnessScreen(key: PageStorageKey('fitness')),
            KeyedSubtree(
              key: const PageStorageKey('profile'),
              child: widget.profileScreen,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }
}

/// The slide-out settings panel opened from the app bar.
///
/// It listens to the app and notification settings notifiers so switches and
/// labels refresh immediately when a preference is changed.
class _QuickSettingsDrawer extends StatelessWidget {
  const _QuickSettingsDrawer({
    required this.onOpenProfile,
    required this.onSignOut,
  });

  final VoidCallback onOpenProfile;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Keep the drawer proportionate on phones while capping its width on larger
    // screens so it does not become excessively wide on tablets or desktop.
    final drawerWidth = min(screenWidth * 0.88, 380.0);

    return Drawer(
      width: drawerWidth,
      child: SafeArea(
        // Rebuild only the drawer contents when either settings notifier changes.
        child: AnimatedBuilder(
          animation: Listenable.merge([
            AppSettings.instance,
            NotificationSettings.instance,
          ]),
          builder: (context, _) {
            final settings = AppSettings.instance;
            final notifications = NotificationSettings.instance;
            final colors = Theme.of(context).colorScheme;

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick Settings',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close settings',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _sectionLabel('PREFERENCES'),
                const SizedBox(height: 8),
                // Measurement system is shared through AppSettings and is
                // reflected throughout screens that display units.
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.straighten),
                            SizedBox(width: 10),
                            Text(
                              'Measurement units',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<MeasurementSystem>(
                            segments: const [
                              ButtonSegment(
                                value: MeasurementSystem.imperial,
                                label: Text('Imperial'),
                              ),
                              ButtonSegment(
                                value: MeasurementSystem.metric,
                                label: Text('Metric'),
                              ),
                            ],
                            selected: {settings.measurementSystem},
                            onSelectionChanged: (selection) {
                              settings.setMeasurementSystem(selection.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          settings.isMetric
                              ? 'Kilometers, kilograms, and centimeters'
                              : 'Miles, pounds, and feet/inches',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                // Theme changes are delegated to the shared settings service.
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: SwitchListTile(
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text(
                      'Dark mode',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Change the app appearance'),
                    value: settings.isDarkMode,
                    onChanged: settings.setDarkMode,
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('NOTIFICATIONS'),
                const SizedBox(height: 8),
                // Notification controls are disabled when notifications are
                // globally off or while the app is requesting permission.
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          secondary: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: const Text(
                            'Notifications',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            notifications.isRequestingPermission
                                ? 'Requesting permission…'
                                : 'Allow Trailblazer to send alerts',
                          ),
                          value: notifications.enabled,
                          onChanged: notifications.isRequestingPermission
                              ? null
                              : (value) async {
                                  final granted = await notifications
                                      .setEnabled(value);
                                  if (!granted && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Notification permission was not granted. You can enable it in your device settings.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.event_outlined),
                          title: const Text('Schedule reminders'),
                          subtitle: const Text(
                            'Alerts before scheduled events',
                          ),
                          value: notifications.scheduleReminders,
                          onChanged: notifications.enabled
                              ? notifications.setScheduleReminders
                              : null,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.today_outlined),
                          title: const Text('Daily summary'),
                          subtitle: const Text(
                            'A quick look at your day ahead',
                          ),
                          value: notifications.dailySummary,
                          onChanged: notifications.enabled
                              ? notifications.setDailySummary
                              : null,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.emoji_events_outlined),
                          title: const Text('Motivation'),
                          subtitle: const Text('Occasional encouragement'),
                          value: notifications.motivation,
                          onChanged: notifications.enabled
                              ? notifications.setMotivation
                              : null,
                        ),
                        // Lets the user choose how far ahead schedule alerts
                        // should be delivered.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Reminder lead time',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              SizedBox(
                                width: 118,
                                child: DropdownButtonFormField<int>(
                                  initialValue:
                                      notifications.reminderLeadMinutes,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 9,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  items: NotificationSettings
                                      .reminderLeadMinuteOptions
                                      .map(
                                        (minutes) => DropdownMenuItem<int>(
                                          value: minutes,
                                          child: Text('$minutes min'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: notifications.enabled
                                      ? (value) {
                                          if (value != null) {
                                            notifications
                                                .setReminderLeadMinutes(value);
                                          }
                                        }
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'These preferences are saved on this device. Notification delivery will be connected to your schedule and daily routines in the next step.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('ACCOUNT'),
                const SizedBox(height: 8),
                // Profile navigation is handled by the parent shell so the
                // drawer can close before the PageView changes destination.
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Profile'),
                        subtitle: const Text('Personal information and goals'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: onOpenProfile,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('SESSION'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text(
                      'Sign out',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: onSignOut,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your preferences are saved on this device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Small visual heading used to separate groups of drawer preferences.
  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: AppColors.trailblazerOrange,
      ),
    );
  }
}
