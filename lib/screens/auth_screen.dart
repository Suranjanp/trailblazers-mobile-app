import 'package:flutter/material.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signUp = false});

  final bool signUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _hidePassword = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Account access is unavailable. You can continue as a guest.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signUp = widget.signUp;
    final title = signUp ? 'Create account' : 'Log in';

    return Scaffold(
      appBar: AppBar(title: const Text('Trailblazer')),
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
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    if (signUp) ...[
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter your name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      validator: (value) {
                        final email = (value ?? '').trim();
                        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(email)
                            ? null
                            : 'Enter a valid email address.';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: signUp
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: signUp ? null : (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password.';
                        }
                        if (signUp && value.length < 8) {
                          return 'Use at least 8 characters.';
                        }
                        return null;
                      },
                    ),
                    if (signUp) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == _password.text && _password.text.isNotEmpty
                            ? null
                            : 'Passwords must match.',
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _submit, child: Text(title)),
                    TextButton(
                      onPressed: signUp
                          ? () => Navigator.pop(context)
                          : () => Navigator.pushNamed(context, '/signup'),
                      child: Text(signUp ? 'Back to login' : 'Sign up'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/home',
                        (_) => false,
                      ),
                      child: const Text('Continue as guest'),
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
