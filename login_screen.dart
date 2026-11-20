import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/cloud_service.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Mode { unlock, create, cloud, recover }

class LoginScreen extends StatefulWidget {
  final Future<void> Function(Session) onUnlocked;
  const LoginScreen({super.key, required this.onUnlocked});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();

  List<LocalAccount> _accounts = [];
  LocalAccount? _selected;
  _Mode _mode = _Mode.create;
  bool _loaded = false;
  bool _hide = true;
  bool _busy = false;
  String? _error;

  bool get _cloudOn => CloudService.configured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AccountService.list();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _selected = list.isEmpty ? null : (_selected != null && list.any((a) => a.id == _selected!.id) ? list.firstWhere((a) => a.id == _selected!.id) : list.first);
      _mode = list.isEmpty ? (_cloudOn ? _Mode.cloud : _Mode.create) : _Mode.unlock;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  void _go(_Mode m) {
    setState(() {
      _mode = m;
      _error = null;
      _pass.clear();
      _confirm.clear();
      _code.clear();
    });
  }

  void _fail(String m) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = m;
    });
  }

  Future<void> _finish(Session s) async {
    await widget.onUnlocked(s);
  }

  // ---- actions ------------------------------------------------------------

  Future<void> _unlock() async {
    final a = _selected;
    if (a == null) return;
    if (_pass.text.isEmpty) return _fail('Enter your password.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final pw = _pass.text;
    final r = await AccountService.unlock(a, pw);
    if (r.status != UnlockStatus.ok) {
      _pass.clear();
      return _fail(r.message);
    }
    await _finish(Session(a, r.dek!, pw));
  }

  Future<void> _create() async {
    final nameProblem =
        AccountService.nameProblem(_name.text, needEmail: _cloudOn);
    if (nameProblem != null) return _fail(nameProblem);
    final pwProblem = AccountService.passwordProblem(_pass.text);
    if (pwProblem != null) return _fail(pwProblem);
    if (_pass.text != _confirm.text) return _fail('Passwords do not match.');
    if (await AccountService.findByName(_name.text) != null) {
      return _fail('This account already exists on this phone. Sign in instead.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final pw = _pass.text;
    final created = await AccountService.create(_name.text, pw);
    if (!mounted) return;
    await showRecoveryCodeDialog(context, created.recoveryCode);
    await _finish(Session(created.account, created.dek, pw));
  }

  Future<void> _cloudSignIn() async {
    final email = _name.text.trim();
    if (!AccountService.looksLikeEmail(email)) return _fail('Enter a valid email address.');
    if (_pass.text.isEmpty) return _fail('Enter your password.');
    if (await AccountService.findByName(email) != null) {
      return _fail('This account is already on this phone. Choose it from the list.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final pw = _pass.text;
    final fetched = await CloudService.instance.signInAndFetch(email, pw);
    if (fetched.error != null) {
      await CloudService.instance.signOutQuietly();
      return _fail(fetched.error == 'offline'
          ? 'No internet connection. Connect and try again.'
          : 'Could not sign in: ${fetched.error}');
    }
    final row = fetched.row;
    if (row == null) {
      await CloudService.instance.signOutQuietly();
      return _fail('No backup was found for this account.');
    }

    var acc = await AccountService.adopt(email, row);
    List<int>? dek;
    final code = _code.text.trim();
    if (code.isNotEmpty) {
      // Forgot the old password: open with the recovery code, then protect
      // the data key with the password typed here.
      dek = await AccountService.dekFromRecovery(
          row['recovery_salt'] as String, row['wrapped_dek_recovery'] as String, code);
      if (dek == null) {
        await AccountService.remove(acc.id);
        await CloudService.instance.signOutQuietly();
        return _fail('That recovery code is not correct.');
      }
      final problem = AccountService.passwordProblem(pw);
      if (problem != null) {
        await AccountService.remove(acc.id);
        await CloudService.instance.signOutQuietly();
        return _fail(problem);
      }
      acc = await AccountService.rewrapPassword(acc, dek, pw);
    } else {
      final r = await AccountService.unlock(acc, pw);
      if (r.status != UnlockStatus.ok) {
        await AccountService.remove(acc.id);
        await CloudService.instance.signOutQuietly();
        return _fail('This password does not open the backup. If you changed '
            'your password, enter your recovery code too.');
      }
      dek = r.dek;
    }
    await CloudService.instance.signOutQuietly();
    await _finish(Session(acc, dek!, pw));
  }

  Future<void> _recover() async {
    final a = _selected;
    if (a == null) return;
    final problem = AccountService.passwordProblem(_pass.text);
    if (problem != null) return _fail(problem);
    if (_pass.text != _confirm.text) return _fail('Passwords do not match.');
    if (_code.text.trim().isEmpty) return _fail('Enter your recovery code.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final dek = await AccountService.dekFromRecovery(
        a.recoverySalt, a.wrappedRecovery, _code.text);
    if (dek == null) return _fail('That recovery code is not correct.');
    final pw = _pass.text;
    final updated = await AccountService.rewrapPassword(a, dek, pw);
    await _finish(Session(updated, dek, pw));
  }

  // ---- UI -----------------------------------------------------------------

  Widget _passField(TextEditingController c, String label,
      {bool last = false, VoidCallback? onDone}) {
    return TextField(
      controller: c,
      obscureText: _hide,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => onDone?.call() : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ),
    );
  }

  Widget _nameField() => TextField(
        controller: _name,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: _cloudOn ? TextInputType.emailAddress : TextInputType.text,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: _cloudOn ? 'Email' : 'Username',
          prefixIcon: Icon(_cloudOn ? Icons.mail_outline : Icons.person_outline),
        ),
      );

  Widget _link(String text, VoidCallback onTap) => TextButton(
        onPressed: _busy ? null : onTap,
        child: Text(text),
      );

  List<Widget> _body() {
    switch (_mode) {
      case _Mode.unlock:
        return [
          if (_accounts.length > 1)
            DropdownButtonFormField<String>(
              value: _selected?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Account', prefixIcon: Icon(Icons.person_outline)),
              items: [
                for (final a in _accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                _selected = _accounts.firstWhere((a) => a.id == v);
                _error = null;
              }),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.line),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline, color: AppTheme.teal),
                const SizedBox(width: 10),
                Expanded(child: Text(_selected?.name ?? '', overflow: TextOverflow.ellipsis)),
              ]),
            ),
          gap(12),
          _passField(_pass, 'Password', last: true, onDone: _unlock),
          if (_error != null) ...[gap(12), NoticeCard(text: _error!, error: true)],
          gap(18),
          _primary('Unlock', _unlock),
          gap(6),
          _link('Forgot password?', () => _go(_Mode.recover)),
          _link('Add or create another account', () => _go(_cloudOn ? _Mode.cloud : _Mode.create)),
        ];
      case _Mode.create:
        return [
          _nameField(),
          gap(12),
          _passField(_pass, 'Password'),
          gap(12),
          _passField(_confirm, 'Confirm password', last: true, onDone: _create),
          gap(8),
          Text(
            _cloudOn
                ? 'Your data is encrypted on this phone and backed up encrypted to '
                    'the cloud, so it survives a reinstall. Only your password or '
                    'recovery code can open it.'
                : 'Your data is encrypted and stays on this phone only. If the app is '
                    'deleted, it is lost.',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (_error != null) ...[gap(12), NoticeCard(text: _error!, error: true)],
          gap(18),
          _primary('Create account', _create),
          if (_cloudOn) _link('I already have a cloud account', () => _go(_Mode.cloud)),
          if (_accounts.isNotEmpty) _link('Back to sign in', () => _go(_Mode.unlock)),
        ];
      case _Mode.cloud:
        return [
          _nameField(),
          gap(12),
          _passField(_pass, 'Password', last: _code.text.isEmpty, onDone: _cloudSignIn),
          gap(12),
          TextField(
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Recovery code (only if you forgot your old password)',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          gap(8),
          const Text(
            'Use this on a new phone or after reinstalling. Your encrypted data '
            'is downloaded and opened with your password.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (_error != null) ...[gap(12), NoticeCard(text: _error!, error: true)],
          gap(18),
          _primary('Sign in and restore', _cloudSignIn),
          _link('Create a new account', () => _go(_Mode.create)),
          if (_accounts.isNotEmpty) _link('Back to sign in', () => _go(_Mode.unlock)),
        ];
      case _Mode.recover:
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.line),
            ),
            child: Text(_selected?.name ?? '', overflow: TextOverflow.ellipsis),
          ),
          gap(12),
          TextField(
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Recovery code', prefixIcon: Icon(Icons.key_outlined)),
          ),
          gap(12),
          _passField(_pass, 'New password'),
          gap(12),
          _passField(_confirm, 'Confirm new password', last: true, onDone: _recover),
          gap(8),
          Text(
            _cloudOn
                ? 'This sets a new password for opening your data on this phone. If '
                    'you also forgot the cloud login password, reset it from your '
                    'Supabase dashboard (Authentication, Users).'
                : 'This sets a new password for opening your data.',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (_error != null) ...[gap(12), NoticeCard(text: _error!, error: true)],
          gap(18),
          _primary('Reset password', _recover),
          _link('Back to sign in', () => _go(_Mode.unlock)),
        ];
    }
  }

  Widget _primary(String text, VoidCallback onTap) => FilledButton(
        onPressed: _busy ? null : onTap,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(text),
      );

  String get _title {
    switch (_mode) {
      case _Mode.unlock:
        return 'Welcome back';
      case _Mode.create:
        return 'Create your account';
      case _Mode.cloud:
        return 'Restore your account';
      case _Mode.recover:
        return 'Reset password';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
                  const Center(child: Appear(from: Offset(0, 8), child: AppLogo(size: 84))),
                  gap(20),
                  Text(_title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                  gap(24),
                  ..._body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

