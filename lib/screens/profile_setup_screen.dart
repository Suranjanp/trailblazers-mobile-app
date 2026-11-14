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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();

  String _goal = 'maintain';
  bool _saving = false;
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

    final savedGoal = saved['bodyGoal'];
    if (savedGoal is String &&
        const ['maintain', 'lose', 'gain'].contains(savedGoal)) {
      _goal = savedGoal;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

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
          }, SetOptions(merge: true));

      if (mounted) {
        if (widget.openedFromProfile) {
          Navigator.of(context).pop();
        } else {
          _goHome();
        }
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

  String? _validateMeasurement(String? value) {
    final number = double.tryParse((value ?? '').trim());
    if (number == null || !number.isFinite || number <= 0) {
      return 'Enter a number greater than zero.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Set up your profile')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Body & goal',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Save your starting information, or skip setup for now.',
                      ),
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
                        validator: (value) {
                          final age = int.tryParse((value ?? '').trim());
                          if (age == null || age < 18 || age > 120) {
                            return 'Enter a whole-number age from 18 to 120.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _height,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          suffixText: 'cm',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateMeasurement,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _weight,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Current weight',
                          suffixText: 'kg',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateMeasurement,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _goal,
                        decoration: const InputDecoration(
                          labelText: 'Body goal',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'maintain',
                            child: Text('Maintain weight'),
                          ),
                          DropdownMenuItem(
                            value: 'lose',
                            child: Text('Lose weight'),
                          ),
                          DropdownMenuItem(
                            value: 'gain',
                            child: Text('Gain weight'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (goal) {
                                if (goal != null) {
                                  setState(() => _goal = goal);
                                }
                              },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
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
      ),
    );
  }
}
