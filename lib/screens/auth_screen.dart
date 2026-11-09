
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import '../widgets/decorative_background.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signUp = false});

  final bool signUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _isLogin = true;
  bool _hidePassword = true;
  bool _rememberMe = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _isLogin = !widget.signUp;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }

    final email = _email.text.trim();
    final password = _password.text;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final auth = FirebaseAuth.instance;

      if (!_isLogin) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Save the user's name to their Firebase profile.
        await credential.user?.updateDisplayName(_name.text.trim());
      } else {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home',
        (_) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      final message = switch (error.code) {
        'email-already-in-use' =>
          'An account already uses this email.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Check your email and password.',
        'weak-password' =>
          'Choose a stronger password.',
        'network-request-failed' =>
          'Check your connection and try again.',
        _ =>
          'Could not complete the request. Please try again.',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();

    if (email.isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email address first.'),
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset email sent. Check your inbox.',
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'user-not-found'
                ? 'No account was found for that email.'
                : 'Could not send reset email. Please try again.',
          ),
        ),
      );
    }
  }

  void _changeMode(bool login) {
    setState(() {
      _isLogin = login;
      _formKey.currentState?.reset();
      _password.clear();
      _confirmPassword.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final signUp = !_isLogin;
    final title = signUp ? 'Create Account' : 'Log In';

    final screenWidth = MediaQuery.of(context).size.width;

    final smallScreen = screenWidth < 360;

    final taglineSize = smallScreen ? 15.0 : 17.0;
    final headingSize = smallScreen ? 20.0 : 22.0;
    final bodySize = smallScreen ? 12.0 : 14.0;
    final buttonSize = smallScreen ? 15.0 : 16.0;
    final tabSize = smallScreen ? 14.0 : 15.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecorativeBackground(),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 440,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Trailblazer logo
                        Center(
                          child: Image.asset(
                            'assets/images/trailblazer_logo.png',
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.explore,
                                size: 90,
                                color: AppColors.navigationNavy,
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        Center(
                          child: Text(
                            'Learn. Plan. Achieve.',
                            style: TextStyle(
                              fontSize: taglineSize,
                              color: AppColors.textBlue,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Login / Signup selector
                        Container(
                          height: 45,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.actionBlue,
                            ),
                            borderRadius: BorderRadius.circular(35),
                          ),
                          child: Row(
                            children: [
                              _buildTab('Log In', true),
                              _buildTab('Sign Up', false),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Page heading
                        Text(
                          title,
                          style: TextStyle(
                            color: AppColors.navigationNavy,
                            fontSize: headingSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 15),

                        // Name field - signup only
                        if (signUp) ...[
                          TextFormField(
                            controller: _name,
                            textCapitalization:
                                TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              'Name',
                              Icons.person_outline,
                            ),
                            validator: (value) {
                              if (!signUp) return null;

                              return (value ?? '').trim().isEmpty
                                  ? 'Enter your name.'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 15),
                        ],

                        // Email field
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: _inputDecoration(
                            'Email Address',
                            Icons.email_outlined,
                          ),
                          validator: (value) {
                            final email = (value ?? '').trim();

                            return RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(email)
                                ? null
                                : 'Enter a valid email address.';
                          },
                        ),

                        const SizedBox(height: 15),

                        // Password field
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: signUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted:
                              signUp ? null : (_) => _submit(),
                          decoration: _inputDecoration(
                            'Password',
                            Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () {
                                setState(() {
                                  _hidePassword = !_hidePassword;
                                });
                              },
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.textBlue,
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

                        // Confirm password - signup only
                        if (signUp) ...[
                          const SizedBox(height: 15),
                          TextFormField(
                            controller: _confirmPassword,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: _inputDecoration(
                              'Confirm Password',
                              Icons.lock_outline,
                            ),
                            validator: (value) {
                              return value == _password.text &&
                                      _password.text.isNotEmpty
                                  ? null
                                  : 'Passwords must match.';
                            },
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Remember Me and Forgot Password
                        if (_isLogin)
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                activeColor: AppColors.navigationNavy,
                                onChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                              ),
                              Expanded(
                                child: Text(
                                  'Remember Me',
                                  style: TextStyle(
                                    color: AppColors.textBlue,
                                    fontSize: bodySize,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _forgotPassword,
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    color: AppColors.navigationNavy,
                                    fontSize: bodySize,
                                  ),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 15),

                        // Main action button
                        SizedBox(
                          height: 45,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.navigationNavy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(35),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    height: 15,
                                    width: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.arrow_forward),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Divider
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(
                                color: AppColors.actionBlue,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Text(
                                'or',
                                style: TextStyle(
                                  color: AppColors.textBlue,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(
                                color: AppColors.actionBlue,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Switch login/signup
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            Text(
                              _isLogin
                                  ? "Don't have an account? "
                                  : 'Already have an account? ',
                              style: const TextStyle(
                                color: AppColors.textBlue,
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _changeMode(!_isLogin),
                              child: Text(
                                _isLogin ? 'Sign Up' : 'Log In',
                                style: const TextStyle(
                                  color: AppColors.trailblazerOrange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Guest login
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamedAndRemoveUntil(
                              context,
                              '/home',
                              (_) => false,
                            );
                          },
                          child: const Text(
                            'Continue as Guest',
                            style: TextStyle(
                              color: AppColors.textBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Login / Signup selector tab
  Widget _buildTab(String title, bool loginTab) {
    final selected = _isLogin == loginTab;

    return Expanded(
      child: GestureDetector(
        onTap: () => _changeMode(loginTab),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.navigationNavy
                : Colors.transparent,
            borderRadius: BorderRadius.circular(35),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textBlue,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // Shared input styling
  InputDecoration _inputDecoration(
    String hint,
    IconData icon,
  ) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textBlue,
        fontSize: 15,
      ),
      prefixIcon: Icon(
        icon,
        color: AppColors.textBlue,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: AppColors.actionBlue,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: AppColors.navigationNavy,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: Colors.red,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 1.5,
        ),
      ),
    );
  }
}
