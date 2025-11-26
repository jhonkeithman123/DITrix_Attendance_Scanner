import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/app_notifier.dart';
import 'reset_password_screen.dart';
import 'dart:math' as math;

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtl = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;
  final _formKey = GlobalKey<FormState>();

  // measure card to decide scrolling
  final GlobalKey _cardKey = GlobalKey();
  bool _needsScroll = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter email';
    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!re.hasMatch(v.trim())) return 'Invalid email';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final resp = await _auth.forgotPassword(email: _emailCtl.text.trim());
      // resp can contain notice/message — show friendly message
      final msg = (resp['message'] != null)
          ? resp['message'].toString()
          : 'Reset code sent if the account exists';
      // navigate to reset screen (user will enter code + new password)
      if (mounted) {
        AppNotifier.showSnack(context, msg);
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ResetPasswordScreen(email: _emailCtl.text.trim())));
      }
    } catch (e) {
      if (!mounted) return;
      final m = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      AppNotifier.showSnack(context, m);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
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
                  TextFormField(
                    controller: _emailCtl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: _validateEmail,
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
                          : const Text('Send reset code'),
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
