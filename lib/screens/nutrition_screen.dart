import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  static const int _dailyCalorieTarget = 2000;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sign in to track your meals.'));
    }

    final foodLogs = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('foodLogs');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final todayLogs = foodLogs
        .where('loggedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('loggedAt', isLessThan: Timestamp.fromDate(tomorrow))
        .orderBy('loggedAt', descending: true);

    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: todayLogs.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load your food log.'));
        }

        final entries = snapshot.data?.docs;
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final entriesByMeal = <String, List<Map<String, dynamic>>>{
          for (final meal in _mealTypes) meal: [],
          'Other': [],
        };

        var totalCalories = 0.0;
        for (final entry in entries) {
          final food = entry.data();
          final meal = entriesByMeal[food['meal']] ?? entriesByMeal['Other']!;
          meal.add(food);
          totalCalories += _entryCalories(food);
        }

        final consumedCalories = totalCalories.round();
        final remainingCalories = _dailyCalorieTarget - consumedCalories;
        final progress = (consumedCalories / _dailyCalorieTarget)
            .clamp(0.0, 1.0)
            .toDouble();

        final calorieStatus = switch (remainingCalories) {
          > 0 => '$remainingCalories kcal remaining',
          0 => 'Target met',
          _ => '${remainingCalories.abs()} kcal over target',
        };

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Calories today', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '$consumedCalories / $_dailyCalorieTarget kcal',
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      semanticsLabel: 'Daily calorie target progress',
                      semanticsValue: calorieStatus,
                    ),
                    const SizedBox(height: 8),
                    Text(calorieStatus),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _AddFoodDialog(foodLogs: foodLogs),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add food'),
            ),
            const SizedBox(height: 16),
            Text('Today’s food log', style: textTheme.titleLarge),
            if (entries.isEmpty)
              const ListTile(title: Text('No food logged today.')),
            for (final meal in entriesByMeal.entries)
              if (meal.value.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(meal.key, style: textTheme.titleMedium),
                ),
                for (final food in meal.value)
                  ListTile(
                    title: Text(food['name'] as String? ?? 'Unnamed food'),
                    subtitle: Text('${food['servings']} serving(s)'),
                    trailing: Text(
                      '${_entryCalories(food).toStringAsFixed(0)} kcal',
                    ),
                  ),
              ],
          ],
        );
      },
    );
  }

  double _entryCalories(Map<String, dynamic> food) {
    final servings = food['servings'] as num? ?? 0;
    final caloriesPerServing = food['caloriesPerServing'] as num? ?? 0;
    return servings.toDouble() * caloriesPerServing.toDouble();
  }
}

class _AddFoodDialog extends StatefulWidget {
  const _AddFoodDialog({required this.foodLogs});

  final CollectionReference<Map<String, dynamic>> foodLogs;

  @override
  State<_AddFoodDialog> createState() => _AddFoodDialogState();
}

class _AddFoodDialogState extends State<_AddFoodDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _servings = TextEditingController(text: '1');
  final _calories = TextEditingController();

  String _meal = _mealTypes.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    _calories.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.foodLogs.add({
        'name': _name.text.trim(),
        'meal': _meal,
        'servings': double.parse(_servings.text.trim()),
        'caloriesPerServing': int.parse(_calories.text.trim()),
        'loggedAt': Timestamp.now(),
      });

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
        _error = 'Could not save food (${error.code}).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add food'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Food name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter a food name.' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _meal,
              decoration: const InputDecoration(labelText: 'Meal'),
              items: [
                for (final meal in _mealTypes)
                  DropdownMenuItem(value: meal, child: Text(meal)),
              ],
              onChanged: _saving
                  ? null
                  : (meal) {
                      if (meal != null) {
                        setState(() => _meal = meal);
                      }
                    },
            ),
            TextFormField(
              controller: _servings,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Servings'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final servings = double.tryParse((value ?? '').trim());
                if (servings == null || !servings.isFinite || servings <= 0) {
                  return 'Enter a number greater than zero.';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _calories,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Calories per serving',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final calories = int.tryParse((value ?? '').trim());
                if (calories == null || calories < 0) {
                  return 'Enter zero or a positive whole number.';
                }
                return null;
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save food'),
        ),
      ],
    );
  }
}
