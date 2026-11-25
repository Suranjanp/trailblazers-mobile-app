import 'package:flutter/material.dart';

import 'health_screen.dart';
import 'nutrition_screen.dart';

/// Combines nutrition, hydration, and sleep under one Health destination.
class HealthHubScreen extends StatefulWidget {
  const HealthHubScreen({super.key});

  @override
  State<HealthHubScreen> createState() => _HealthHubScreenState();
}

class _HealthHubScreenState extends State<HealthHubScreen>
    with AutomaticKeepAliveClientMixin<HealthHubScreen> {
  int _selectedTab = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: colors.surface,
            child: TabBar(
              onTap: (index) {
                setState(() => _selectedTab = index);
              },
              labelColor: colors.primary,
              unselectedLabelColor: colors.onSurfaceVariant,
              indicatorColor: colors.primary,
              dividerColor: colors.outlineVariant,
              tabs: const [
                Tab(icon: Icon(Icons.restaurant_outlined), text: 'Nutrition'),
                Tab(icon: Icon(Icons.favorite_outline), text: 'Wellness'),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: const [
                NutritionScreen(key: PageStorageKey('health-nutrition')),
                HealthScreen(key: PageStorageKey('health-wellness')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}