import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_notifier.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;

  // UI state
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _agree = false;
  int _pwScore = 0;

  @override
  void initState() {
    super.initState();
    _passCtl.addListener(_updateStrength);
  }

  void _updateStrength() {
    final s = _passCtl.text;
    int score = 0;
    if (s.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(s)) score++;
    if (RegExp(r'[0-9]').hasMatch(s)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(s)) score++;
    setState(() => _pwScore = score);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agree) {
      AppNotifier.showSnack(context, 'Please agree to the terms');
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await _auth.signUp(
          email: _emailCtl.text.trim(), password: _passCtl.text);
      setState(() => _loading = false);
      if (ok) {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Account created. Please sign in.');
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Signup failed');
      }
    } catch (e) {
      setState(() => _loading = false);
      AppNotifier.showSnack(context, 'Signup error: $e');
    }
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.removeListener(_updateStrength);
    _passCtl.dispose();
    _confirmCtl.dispose();
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
    if (v.length < 8) return 'Minimum 8 characters';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Include at least one number';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return 'Include letters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Confirm password';
    if (v != _passCtl.text) return 'Passwords do not match';
    return null;
  }

  Color _strengthColor() {
    switch (_pwScore) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.lightGreen;
      default:
        return Colors.green;
    }
  }

  String _strengthLabel() {
    switch (_pwScore) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        flexibleSpace: Container(
            decoration: BoxDecoration(gradient: AppGradients.of(context))),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                          icon: Icon(_showPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: _validatePass,
                    ),
                    // show password strength only when user has typed something
                    if (_passCtl.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // password strength bar
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: (_pwScore / 4).clamp(0.0, 1.0),
                              color: _strengthColor(),
                              backgroundColor: Colors.grey.shade300,
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_strengthLabel(),
                              style: TextStyle(color: _strengthColor())),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtl,
                      obscureText: !_showConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        suffixIcon: IconButton(
                          icon: Icon(_showConfirm
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _showConfirm = !_showConfirm),
                        ),
                      ),
                      validator: _validateConfirm,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _agree,
                          onChanged: (v) => setState(() => _agree = v ?? false),
                        ),
                        const Expanded(
                          child:
                              Text('I agree to the Terms and Privacy Policy'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_loading || !_agree) ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account?'),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                          builder: (_) => const LoginScreen()));
                                },
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
