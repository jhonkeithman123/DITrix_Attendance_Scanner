import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_notifier.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'dart:math' as math;
import 'verify_email_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;

  // UI state
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _agree = false;
  int _pwScore = 0;

  final GlobalKey _cardKey = GlobalKey();
  bool _needScroll = false;

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
      final resp = await _auth.signUp(
          email: _emailCtl.text.trim(),
          password: _passCtl.text,
          name: _nameCtl.text.trim());

      final status = resp['status']?.toString() ?? 'ok';
      final notice = resp['notice']?.toString();

      if (status == 'ok') {
        if (!mounted) return;

        if (notice != null) {
          final friendly = notice == 'account_created_email_failed'
              ? 'Account created but failed to send verification email.'
              : 'Verification code sent to your email';
          AppNotifier.showSnack(context, friendly);
          Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                    email: _emailCtl.text.trim(),
                    notice: friendly,
                  )));
        } else {
          AppNotifier.showSnack(context, 'Account created. Please sign in.');
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      } else {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Signup failed');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      AppNotifier.showSnack(context, msg);
    } finally {
      if (mounted) setState(() => _loading = false);
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Create account'),
        flexibleSpace: Container(
            decoration: BoxDecoration(gradient: AppGradients.of(context))),
      ),
      body: LayoutBuilder(builder: (ctx, constraints) {
        final maxWidth = math.min(520.0, constraints.maxWidth * 0.95);
        final horizontalPadding = math.min(24.0, constraints.maxWidth * 0.04);
        final verticalPadding = 16.0 * 2;

        // form card (extracted for clarity)
        final formCard = ConstrainedBox(
          key: _cardKey,
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                      controller: _nameCtl,
                      keyboardType: TextInputType.name,
                      decoration: const InputDecoration(labelText: 'Name'),
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
                    if (_passCtl.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
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
                            onChanged: (v) =>
                                setState(() => _agree = v ?? false)),
                        const Expanded(
                            child: Text(
                                'I agree to the Terms and Privacy Policy')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_loading || !_agree) ? null : _submit,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: _loading
                              ? const SizedBox(
                                  key: ValueKey('spinner'),
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create account',
                                  key: ValueKey('label')),
                        ),
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
                  ],
                ),
              ),
            ),
          ),
        );

        // measeure after layout to decide if scrollion is required
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final rb = _cardKey.currentContext?.findRenderObject() as RenderBox?;
          final cardHeight = rb?.size.height ?? 0;
          final fits = cardHeight + verticalPadding <= constraints.maxHeight;
          final shouldScroll = !fits;
          if (_needScroll != shouldScroll) {
            setState(() => _needScroll = shouldScroll);
          }
        });

        final scrollPhysics = _needScroll
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics();

        // The SingleChildScrollView + ConstrainedBox(minHeight) pattern centers the form
        // when it fits, and allows scrolling only when overflow occurs.
        return Stack(
          children: [
            SingleChildScrollView(
              physics: scrollPhysics,
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  // center vertically when there's extra space
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    formCard,
                  ],
                ),
              ),
            ),

            // loading overlay: fades in and blocks input while submitting
            IgnorePointer(
              ignoring: !_loading,
              child: AnimatedOpacity(
                opacity: _loading ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _loading
                    ? Container(
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      }),
    );
  }
}
