import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_setup_screen.dart';

import '../theme/app_colors.dart';
import '../widgets/decorative_background.dart';

/// Displays the authentication screen and lets a visitor log in, create an
/// account, reset a password, or continue with an anonymous guest account.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signUp = false});

  /// When true, the screen opens in account-creation mode instead of login.
  final bool signUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // The form key lets us validate all visible fields before submitting.
  final _formKey = GlobalKey<FormState>();

  // Controllers keep the text entered by the user available to the handlers.
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _confirmPassword = TextEditingController();

  // Screen and form state.
  bool _isLogin = true;
  bool _hidePassword = true;
  bool _rememberMe = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    // Use the constructor setting to choose the initial tab.
    _isLogin = !widget.signUp;
  }

  @override
  void dispose() {
    // Always release text controllers when this screen is removed.
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  /// Clears the authentication flow from the navigation stack and opens Home.
  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  /// Signs the visitor in anonymously so they can use the app without
  /// creating an account.
  Future<void> _continueAsGuest() async {
    if (_submitting) return;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final auth = FirebaseAuth.instance;

      // Avoid creating another anonymous session if one is already active.
      if (auth.currentUser?.isAnonymous != true) {
        await auth.signInAnonymously();
      }

      if (mounted) {
        _goHome();
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Guest sign-in failed (${error.code}).')),
        );
      }
    } finally {
      // The screen may have been closed while Firebase was processing.
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Validates the form, then either creates a new account or logs in.
  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }

    // Read the field values once before starting the asynchronous request.
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final auth = FirebaseAuth.instance;

      if (!_isLogin) {
        // New accounts are created with Firebase Authentication.
        final credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = credential.user;
        if (!mounted || user == null) return;

        // New users complete their profile before entering the main app.
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProfileSetupScreen(userId: user.uid, initialName: name),
          ),
          (_) => false,
        );
        return;
      } else {
        // Existing users sign in with their email and password.
        await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;

      // Successful login takes the user directly to the Home route.
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      // Convert common Firebase error codes into messages that are useful
      // without exposing technical details to the person using the app.
      final message = switch (error.code) {
        'email-already-in-use' => 'An account already uses this email.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'Check your email and password.',
        'weak-password' => 'Choose a stronger password.',
        'network-request-failed' => 'Check your connection and try again.',
        _ => 'Could not complete the request. Please try again.',
      };

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;

      // Handle unexpected errors with a general message.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Sends a password-reset email for the address currently in the email
  /// field. The user must enter a valid-looking address first.
  Future<void> _forgotPassword() async {
    final email = _email.text.trim();

    if (email.isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Check your inbox.'),
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

  /// Switches between login and sign-up modes and clears password fields so
  /// credentials from one mode are not carried into the other.
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

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Preserve the Trailblazer navy in light mode while using the active
    // theme's primary color in dark mode for better contrast.
    final actionColor =
        isDark ? colors.primary : AppColors.navigationNavy;

    // Slightly reduce text sizes on narrow phones to avoid cramped layouts.
    final screenWidth = MediaQuery.of(context).size.width;
    final smallScreen = screenWidth < 360;

    final taglineSize = smallScreen ? 15.0 : 17.0;
    final headingSize = smallScreen ? 20.0 : 22.0;
    final bodySize = smallScreen ? 12.0 : 14.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Decorative artwork fills the background behind the form.
          const Positioned.fill(child: DecorativeBackground()),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // App logo, with a built-in icon if the asset is
                        // unavailable (for example, during development).
                        Center(
                          child: Image.asset(
                            'assets/images/top_icon.png',
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.explore,
                                size: 90,
                                color: colors.onSurface,
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
                              color: colors.onSurface,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Login / signup selector. Each tab uses its own
                        // brand color when selected.
                        Container(
                          height: 45,
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.outline),
                            borderRadius: BorderRadius.circular(35),
                          ),
                          child: Row(
                            children: [
                              _buildTab(
                                'Log In',
                                true,
                                AppColors.navigationNavy,
                              ),
                              _buildTab(
                                'Sign Up',
                                false,
                                AppColors.trailblazerOrange,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          title,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: headingSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 15),

                        // Name is only requested when creating a new account.
                        if (signUp) ...[
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
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

                        // Email is required in both login and signup modes.
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

                            return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(email)
                                ? null
                                : 'Enter a valid email address.';
                          },
                        ),

                        const SizedBox(height: 15),

                        // Password field. The eye button toggles whether the
                        // entered password is visible.
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: signUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: signUp ? null : (_) => _submit(),
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
                                color: colors.onSurfaceVariant,
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

                        // New accounts must enter the same password twice.
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

                        // These account options are shown only while logging
                        // in. The remember-me checkbox currently tracks its
                        // visual selection in this screen's state.
                        if (_isLogin)
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                activeColor: colors.primary,
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
                                    color: colors.onSurfaceVariant,
                                    fontSize: bodySize,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _forgotPassword,
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontSize: bodySize,
                                  ),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 15),

                        // Main submit button. It is disabled during a
                        // Firebase request and shows a small progress spinner.
                        SizedBox(
                          height: 45,
                          child: FilledButton(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: actionColor,
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
                                    mainAxisAlignment: MainAxisAlignment.center,
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

                        // Visual separator between account actions and the
                        // alternate login/signup and guest options.
                        Row(
                          children: [
                            Expanded(
                              child: Divider(color: colors.outlineVariant),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Text(
                                'or',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(color: colors.outlineVariant),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Offers the opposite account mode without leaving
                        // the authentication screen.
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            Text(
                              _isLogin
                                  ? "Don't have an account? "
                                  : 'Already have an account? ',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
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

                        // Guest access creates or reuses an anonymous
                        // Firebase Authentication session.
                        TextButton(
                          onPressed:
                              _submitting ? null : _continueAsGuest,
                          child: Text(
                            'Continue as Guest',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
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

  /// Builds one side of the login/signup selector.
  ///
  /// The selected tab receives its brand background color; the inactive tab
  /// remains transparent and uses the current theme's secondary text color.
  Widget _buildTab(String title, bool loginTab, Color tabColor) {
    final selected = _isLogin == loginTab;
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: () => _changeMode(loginTab),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tabColor : Colors.transparent,
            borderRadius: BorderRadius.circular(35),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: selected ? Colors.white : colors.onSurfaceVariant,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Creates the shared decoration used by the authentication text fields.
  ///
  /// Centralizing the borders, icons, hint text, and spacing keeps the form
  /// fields visually consistent and makes future styling changes easier.
  InputDecoration _inputDecoration(String hint, IconData icon) {
    final colors = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: colors.onSurfaceVariant,
        fontSize: 15,
      ),
      prefixIcon: Icon(
        icon,
        color: colors.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: colors.primary,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }
}
