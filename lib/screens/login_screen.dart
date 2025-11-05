import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_notifier.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  // ignore: unused_field
  final _auth = AuthService();
  bool _loading = false;
  bool _showPassword = false;
  final _formKey = GlobalKey<FormState>();

  // measure the form card to decide if scrolling is required
  final GlobalKey _cardKey = GlobalKey();
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter email';
    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!re.hasMatch(v.trim())) return 'Invalid email';
    return null;
  }

  String? _validatePass(String? v) {
    if (v == null || v.isEmpty) return 'Enter password';
    return null;
  }

  Future<void> _checkExistingSession() async {
    try {
      final profile = await _auth.validateSession();
      if (profile != null && mounted) {
        // optional: persist profile locally to SharedPreferences for profile screen
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'profile_name', profile['name']?.toString() ?? '');
        await prefs.setString(
            'profile_email', profile['email']?.toString() ?? '');
        if (profile['avatar_url'] != null) {
          await prefs.setString(
              'profile_avatar', profile['avatar_url'].toString());
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      // ignore: don't block UI for session check errors
    }
  }

  Future<void> _submit() async {
    // for development
    // if (!mounted) return;
    // AppNotifier.showSnack(
    //   context,
    //   'Not availabled yet, stay tuned for more updates.',
    // );

    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final ok = await _auth.signIn(
        email: _emailCtl.text.trim(),
        password: _passCtl.text,
      );
      if (ok) {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Signed in');
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const HomeScreen()));
      } else {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Sign in failed');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      AppNotifier.showSnack(context, msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final maxWidth = 520.0;
          final horizontalPadding = math.min(24.0, constraints.maxWidth * 0.04);
          final verticalPadding = 24.0 * 2;

          final formCard = ConstrainedBox(
            key: _cardKey,
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _emailCtl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passCtl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: _validatePass,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _loading
                                ? const SizedBox(
                                    key: ValueKey('spinner'),
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign in', key: ValueKey('label')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SignupScreen(),
                                      ),
                                    );
                                  },
                            child: const Text('Create account'),
                          ),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordScreen(),
                                      ),
                                    );
                                  },
                            child: const Text('Forgot password?'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          // measure after layout to decide if scrolling is required
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final rb =
                _cardKey.currentContext?.findRenderObject() as RenderBox?;
            final cardHeight = rb?.size.height ?? 0;
            final fits = cardHeight + verticalPadding <= constraints.maxHeight;
            final shouldScroll = !fits;
            if (_needsScroll != shouldScroll) {
              setState(() => _needsScroll = shouldScroll);
            }
          });

          final scrollPhysics = _needsScroll
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics();

          return SingleChildScrollView(
            physics: scrollPhysics,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [formCard],
              ),
            ),
          );
        },
      ),
    );
  }
}
