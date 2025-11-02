import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_notifier.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final dynamic notice;
  const VerifyEmailScreen({super.key, required this.email, this.notice});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeCtl = TextEditingController();
  final _focus = FocusNode();
  final _auth = AuthService();
  bool _loading = false;

  Timer? _timer;
  int _seconds = 0; // resend cooldown

  @override
  void initState() {
    super.initState();
    _startCooldown(widget.notice != null
        ? 30
        : 0); // initial cooldown so user doesn't spam resend immediately
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _seconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) {
        t.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds -= 1);
      }
    });
  }

  String get _code => _codeCtl.text.trim();

  Future<void> _submit() async {
    if (_code.length != 6) {
      AppNotifier.showSnack(context, 'Enter the 6-digit code');
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await _auth.verifyEmail(email: widget.email, code: _code);
      if (ok) {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Email verified. Please sign in.');
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Verification failed');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      AppNotifier.showSnack(context, msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0) return;
    setState(() => _loading = true);
    try {
      await _auth.resendVerification(email: widget.email);
      AppNotifier.showSnack(context, 'Verification code resent');
      _startCooldown(60);
    } catch (e) {
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      AppNotifier.showSnack(context, msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _buildPinBoxes() {
    final code = _code.padRight(6);
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (i) {
          final ch = code[i];
          final filled = i < _code.length;
          return Container(
            width: 44,
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? Colors.blue.shade700 : Colors.transparent,
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              filled ? ch : '',
              style: const TextStyle(fontSize: 20, color: Colors.white),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify email'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24),
            child: Column(
              children: [
                if (widget.notice != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.yellow.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.notice?.toString() ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
                Text(
                  'Enter the 6-digit code sent to',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 6),
                Text(widget.email,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey.shade300)),
                const SizedBox(height: 18),
                // hidden textfield captures input
                Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _codeCtl,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 6),
                _buildPinBoxes(),
                const SizedBox(height: 18),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify', key: ValueKey('label')),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: (_seconds == 0 && !_loading) ? _resend : null,
                      child: Text(_seconds == 0
                          ? 'Resend code'
                          : 'Resend in ${_seconds}s'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                  child: const Text('Back to Sign in'),
                ),
              ],
            ),
          ),

          // loading overlay
          IgnorePointer(
            ignoring: !_loading,
            child: AnimatedOpacity(
              opacity: _loading ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: _loading
                  ? Container(
                      color: Colors.black45,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
