import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  final bool createMode;
  final Future<void> Function() onUnlocked;
  const LoginScreen({super.key, required this.createMode, required this.onUnlocked});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _user.text.trim();
    final pass = _pass.text;
    if (user.length < 3) {
      setState(() => _error = 'Username must be at least 3 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (widget.createMode) {
      final problem = AuthService.passwordProblem(pass);
      if (problem != null) {
        setState(() {
          _busy = false;
          _error = problem;
        });
        return;
      }
      if (pass != _confirm.text) {
        setState(() {
          _busy = false;
          _error = 'Passwords do not match.';
        });
        return;
      }
      await AuthService.createAccount(user, pass);
      await widget.onUnlocked();
    } else {
      final r = await AuthService.login(user, pass);
      if (r.status == LoginStatus.ok) {
        await widget.onUnlocked();
      } else if (mounted) {
        setState(() {
          _busy = false;
          _error = r.message;
          _pass.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final create = widget.createMode;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppTheme.teal, Color(0xFF63C7B8)]),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.flight_takeoff,
                        color: Colors.white, size: 34),
                  ),
                  gap(20),
                  Text(create ? 'Welcome aboard' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink)),
                  gap(6),
                  Text(
                    create
                        ? 'Create your private login. It stays on this phone, encrypted.'
                        : 'Sign in to continue to your desk.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  gap(28),
                  TextField(
                    controller: _user,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  gap(12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction:
                        create ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: create ? null : (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (create) ...[
                    gap(12),
                    TextField(
                      controller: _confirm,
                      obscureText: _hide,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline)),
                    ),
                    gap(8),
                    const Text('Use 8+ characters with letters and numbers. '
                        'There is no password recovery, so keep it safe.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  ],
                  if (_error != null) ...[gap(12), NoticeCard(text: _error!, error: true)],
                  gap(20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : Text(create ? 'Create account' : 'Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
