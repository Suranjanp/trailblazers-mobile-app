
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:test_ap_1/theme/app_colors.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  // Daily goals
  final int waterGoal = 2000;
  final double sleepGoal = 8.0;

  // Current progress
  int waterIntake = 0;
  double sleepHours = 0;

  // Add water
  void _addWater(int amount) {
    setState(() {
      waterIntake += amount;
    });
  }

  // Reset water
  void _resetWater() {
    setState(() {
      waterIntake = 0;
    });
  }

  // Record sleep
  Future<void> _logSleep() async {
    final controller = TextEditingController(
      text: sleepHours == 0 ? '' : sleepHours.toString(),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Sleep'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration: const InputDecoration(
            labelText: 'Hours slept',
            hintText: 'Example: 7.5',
            suffixText: 'hours',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final hours = double.tryParse(controller.text);

              if (hours != null && hours > 0 && hours <= 24) {
                Navigator.pop(context, hours);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result != null && mounted) {
      setState(() {
        sleepHours = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final waterProgress = (waterIntake / waterGoal)
        .clamp(0.0, 1.0)
        .toDouble();

    final sleepProgress = (sleepHours / sleepGoal)
        .clamp(0.0, 1.0)
        .toDouble();

    final currentDate = DateFormat('EEEE, MMMM d')
        .format(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Header
          Text(
            'Your Health',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.navigationNavy,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            currentDate,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 24),

          // Daily summary
          _buildSectionTitle('Daily Overview'),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.water_drop,
                  title: 'Water',
                  value: '$waterIntake ml',
                  color: Colors.blue,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.bedtime,
                  title: 'Sleep',
                  value: '${sleepHours.toStringAsFixed(1)} hrs',
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          
// Water tracker
_buildSectionTitle('Water Intake'),

const SizedBox(height: 12),

_buildTrackerCard(
  child: Column(
    children: [
      const Text(
        'Your Daily Hydration',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 24),

      // Circular water tracker
      SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background circle
            SizedBox(
              width: 210,
              height: 210,
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 13,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.blue.shade50,
                ),
              ),
            ),

            // Progress circle
            SizedBox(
              width: 210,
              height: 210,
              child: CircularProgressIndicator(
                value: waterProgress,
                strokeWidth: 13,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.blue,
                ),
              ),
            ),

            // Center water button
            SizedBox(
              width: 145,
              height: 145,
              child: ElevatedButton(
                onPressed: () => _addWater(250),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade800,
                  elevation: 0,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.water_drop,
                      size: 38,
                    ),
                    SizedBox(height: 5),
                    Text(
                      '+250 ml',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Add a cup',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 22),

      Text(
        '$waterIntake ml',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),

      Text(
        'of $waterGoal ml daily goal',
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 14,
        ),
      ),

      const SizedBox(height: 16),

      Text(
        waterIntake >= waterGoal
            ? 'Daily water goal reached!'
            : '${waterGoal - waterIntake} ml remaining',
        style: const TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.w600,
        ),
      ),

      const SizedBox(height: 12),

      TextButton.icon(
        onPressed: _resetWater,
        icon: const Icon(Icons.refresh),
        label: const Text('Reset water intake'),
      ),
    ],
  ),
),


          
// Sleep tracker
_buildSectionTitle('Sleep Tracking'),

const SizedBox(height: 12),

_buildTrackerCard(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const Icon(
        Icons.bedtime,
        color: Colors.deepPurple,
        size: 38,
      ),

      const SizedBox(height: 12),

      const Text(
        "Last Night's Sleep",
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 18),

      Text(
        '${sleepHours.toStringAsFixed(1)} hours',
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
        ),
      ),

      const SizedBox(height: 14),

      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LinearProgressIndicator(
          value: sleepProgress,
          minHeight: 14,
          backgroundColor: Colors.deepPurple.shade50,
          color: Colors.deepPurple,
        ),
      ),

      const SizedBox(height: 10),

      Text(
        'Daily goal: ${sleepGoal.toStringAsFixed(0)} hours',
        style: TextStyle(
          color: Colors.grey.shade600,
        ),
      ),

      const SizedBox(height: 20),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _logSleep,
          icon: const Icon(Icons.edit),
          label: Text(
            sleepHours == 0
                ? 'Log Sleep Hours'
                : 'Edit Sleep Hours',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navigationNavy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    ],
  ),
),


          // Encouragement
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.navigationNavy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 28,
                ),

                SizedBox(width: 14),

                Expanded(
                  child: Text(
                    'Small healthy habits make a big difference. '
                    'Keep taking care of yourself!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Section headings
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.bold,
        color: AppColors.navigationNavy,
      ),
    );
  }

  // Summary cards
  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Tracker card container
  Widget _buildTrackerCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // Water buttons
  Widget _waterButton(int amount) {
    return OutlinedButton(
      onPressed: () => _addWater(amount),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blue,
        side: const BorderSide(color: Colors.blue),
      ),
      child: Text('+$amount ml'),
    );
  }
}
