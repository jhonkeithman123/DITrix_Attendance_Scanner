import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/app_notifier.dart';
import 'login_screen.dart';
import 'dart:math' as math;

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  final _formKey = GlobalKey<FormState>();

  final GlobalKey _cardKey = GlobalKey();
  bool _needsScroll = false;

  // single eye toggle to reveal/hide all password fields
  bool _showPasswords = false;

  @override
  void dispose() {
    _codeCtl.dispose();
    _passCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  String? _validateCode(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter code';
    if (v.trim().length < 4) return 'Invalid code';
    return null;
  }

  String? _validatePass(String? v) {
    if (v == null || v.isEmpty) return 'Enter password';
    if (v.length < 8) return 'Minimum 8 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Confirm password';
    if (v != _passCtl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _auth.resetPassword(
        email: widget.email,
        code: _codeCtl.text.trim(),
        newPassword: _passCtl.text,
      );
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Password reset. Please sign in.');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()));
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
      appBar: AppBar(title: const Text('Reset password')),
      body: LayoutBuilder(builder: (ctx, constraints) {
        final maxWidth = math.min(520.0, constraints.maxWidth * 0.95);
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Enter the code sent to ${widget.email}',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _codeCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Code'),
                    validator: _validateCode,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtl,
                    obscureText: !_showPasswords,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPasswords
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _showPasswords = !_showPasswords),
                      ),
                    ),
                    validator: _validatePass,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtl,
                    obscureText: !_showPasswords,
                    decoration:
                        const InputDecoration(labelText: 'Confirm password'),
                    validator: _validateConfirm,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Reset password'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final rb = _cardKey.currentContext?.findRenderObject() as RenderBox?;
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
          padding:
              EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [formCard],
            ),
          ),
        );
      }),
    );
  }
}
