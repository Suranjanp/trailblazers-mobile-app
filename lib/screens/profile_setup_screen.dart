import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.userId,
    required this.initialName,
    this.savedProfile = const {},
    this.openedFromProfile = false,
  });

  final String userId;
  final String initialName;
  final Map<String, dynamic> savedProfile;
  final bool openedFromProfile;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  static const _goals = {
    'maintain': 'Maintain weight',
    'lose': 'Lose weight',
    'gain': 'Gain weight',
  };

  static const _activityLevels = {
    'inactive': 'Inactive',
    'lowActive': 'Low active',
    'active': 'Active',
    'veryActive': 'Very active',
  };

  static const _equations = {'female': 'Female', 'male': 'Male'};

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _calorieTarget = TextEditingController();

  String _goal = 'maintain';
  String? _equation;
  String? _activity;
  bool _eligibleForEstimate = false;
  bool _saving = false;
  int? _suggestion;
  String? _estimateMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = widget.savedProfile;
    final savedName = saved['name'];
    _name = TextEditingController(
      text: savedName is String ? savedName : widget.initialName,
    );
    _age.text = saved['ageYears']?.toString() ?? '';
    _height.text = saved['heightCm']?.toString() ?? '';
    _weight.text = saved['weightKg']?.toString() ?? '';
    _calorieTarget.text = saved['calorieTarget']?.toString() ?? '';

    final savedGoal = saved['bodyGoal'];
    if (savedGoal is String && _goals.containsKey(savedGoal)) {
      _goal = savedGoal;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _calorieTarget.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    if (FirebaseAuth.instance.currentUser?.uid != widget.userId) {
      setState(() => _error = 'Your session changed. Please sign in again.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .set({
            'name': _name.text.trim(),
            'ageYears': int.parse(_age.text.trim()),
            'heightCm': double.parse(_height.text.trim()),
            'weightKg': double.parse(_weight.text.trim()),
            'bodyGoal': _goal,
            'calorieTarget': int.tryParse(_calorieTarget.text.trim()),
          }, SetOptions(merge: true));

      if (!mounted) return;
      if (widget.openedFromProfile) {
        Navigator.of(context).pop();
      } else {
        _goHome();
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not save your profile (${error.code}). Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _clearEstimate() {
    _suggestion = null;
    _estimateMessage = null;
  }

  void _showEstimateMessage(String message) {
    setState(() {
      _suggestion = null;
      _estimateMessage = message;
    });
  }

  void _calculateSuggestion() {
    final age = int.tryParse(_age.text.trim());
    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    final equation = _equation;
    final activity = _activity;

    if (!_eligibleForEstimate ||
        age == null ||
        age < 19 ||
        age > 120 ||
        height == null ||
        !height.isFinite ||
        height <= 0 ||
        weight == null ||
        !weight.isFinite ||
        weight <= 0 ||
        equation == null ||
        activity == null) {
      _showEstimateMessage(
        'Check your age, height, and weight. Select an equation and activity '
        'level, and confirm that the estimate applies to you.',
      );
      return;
    }

    final heightMetres = height / 100;
    final bmi = weight / (heightMetres * heightMetres);
    if (_goal == 'lose' && bmi < 25) {
      _showEstimateMessage(
        'A weight-loss estimate is unavailable for these measurements. '
        'You can leave the target blank or enter one manually.',
      );
      return;
    }

    // Adult Estimated Energy Requirement equations, 2023 DRI Table S-3.
    final maintenance = switch ((equation, activity)) {
      ('male', 'inactive') =>
        753.07 - 10.83 * age + 6.50 * height + 14.10 * weight,
      ('male', 'lowActive') =>
        581.47 - 10.83 * age + 8.30 * height + 14.94 * weight,
      ('male', 'active') =>
        1004.82 - 10.83 * age + 6.52 * height + 15.91 * weight,
      ('male', 'veryActive') =>
        -517.88 - 10.83 * age + 15.61 * height + 19.11 * weight,
      ('female', 'inactive') =>
        584.90 - 7.01 * age + 5.72 * height + 11.71 * weight,
      ('female', 'lowActive') =>
        575.77 - 7.01 * age + 6.60 * height + 12.14 * weight,
      ('female', 'active') =>
        710.25 - 7.01 * age + 6.54 * height + 12.34 * weight,
      ('female', 'veryActive') =>
        511.83 - 7.01 * age + 9.07 * height + 12.56 * weight,
      _ => double.nan,
    };

    final estimate = switch (_goal) {
      'lose' => maintenance - 500,
      'gain' => maintenance + 300,
      _ => maintenance,
    };

    // Suppress unusually low or high automatic estimates.
    final minimum = equation == 'female' ? 1500 : 1800;
    if (!estimate.isFinite || estimate < minimum || estimate > 6000) {
      _showEstimateMessage(
        'An automatic target is unavailable for these inputs. '
        'Check your measurements or enter a target manually.',
      );
      return;
    }

    setState(() {
      _suggestion = (estimate / 50).round() * 50;
      _estimateMessage = null;
    });
  }

  Widget _measurementField(
    TextEditingController controller,
    String label,
    String units,
  ) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        suffixText: units,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(_clearEstimate),
      validator: (value) {
        final number = double.tryParse((value ?? '').trim());
        if (number == null || !number.isFinite || number <= 0) {
          return 'Enter a number greater than zero.';
        }
        return null;
      },
    );
  }

  Widget _choiceField({
    required String label,
    required String? value,
    required Map<String, String> choices,
    required ValueChanged<String> onSelected,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final choice in choices.entries)
          DropdownMenuItem(value: choice.key, child: Text(choice.value)),
      ],
      onChanged: _saving
          ? null
          : (selected) {
              if (selected == null) return;
              setState(() {
                onSelected(selected);
                _clearEstimate();
              });
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = _suggestion;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.openedFromProfile ? 'Edit profile' : 'Set up your profile',
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 488),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Body & goal', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Enter your name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _age,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Age in years',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(_clearEstimate),
                      validator: (value) {
                        final age = int.tryParse((value ?? '').trim());
                        if (age == null || age < 18 || age > 120) {
                          return 'Enter a whole-number age from 18 to 120.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _measurementField(_height, 'Height', 'cm'),
                    const SizedBox(height: 16),
                    _measurementField(_weight, 'Current weight', 'kg'),
                    const SizedBox(height: 16),
                    _choiceField(
                      label: 'Body goal',
                      value: _goal,
                      choices: _goals,
                      onSelected: (value) => _goal = value,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Calorie estimate (optional)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose your usual activity level. You can also enter '
                      'your own target below.',
                    ),
                    const SizedBox(height: 12),
                    _choiceField(
                      label: 'Sex used for the estimate',
                      value: _equation,
                      choices: _equations,
                      onSelected: (value) => _equation = value,
                    ),
                    const SizedBox(height: 12),
                    _choiceField(
                      label: 'Usual activity level',
                      value: _activity,
                      choices: _activityLevels,
                      onSelected: (value) => _activity = value,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _eligibleForEstimate,
                      title: const Text(
                        'I am 19 or older and am neither pregnant nor '
                        'breastfeeding.',
                      ),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _eligibleForEstimate = value ?? false;
                                _clearEstimate();
                              });
                            },
                    ),
                    OutlinedButton(
                      onPressed: _saving ? null : _calculateSuggestion,
                      child: const Text('Calculate suggestion'),
                    ),
                    if (_estimateMessage case final String message)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(message),
                      ),
                    if (suggestion != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Suggested daily target: $suggestion kcal',
                        style: theme.textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => _calorieTarget.text = suggestion.toString(),
                        child: const Text('Use suggestion'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _calorieTarget,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Daily calorie target (optional)',
                        suffixText: 'kcal',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final input = (value ?? '').trim();
                        if (input.isEmpty) return null;
                        final target = int.tryParse(input);
                        return target == null || target <= 0
                            ? 'Enter a positive whole number.'
                            : null;
                      },
                    ),
                    if (_error case final String message)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          message,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save profile'),
                    ),
                    if (!widget.openedFromProfile)
                      TextButton(
                        onPressed: _saving ? null : _goHome,
                        child: const Text('Skip for now'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
