import 'package:flutter/material.dart';
import 'package:student_id_scanner/screens/signup_screen.dart';
import '../utils/app_notifier.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  final _auth = AuthService();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final ok = await _auth.signIn(
          email: _emailCtrl.text.trim(), password: _passCtrl.text);
      if (!ok) {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Login failed');
        return;
      }
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Login successful');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      AppNotifier.showSnack(context, 'Login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter email';
    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!re.hasMatch(v.trim())) return 'Invalid email';
    return null;
  }

  String? _validatePass(String? v) {
    if (v == null || v.isEmpty) return 'Enter password';
    if (v.length < 4) return 'Too short';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: _validatePass,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign in'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SignupScreen()));
                      },
                      child: const Text('Sign up'),
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
