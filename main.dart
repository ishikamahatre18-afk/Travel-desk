import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TravelDeskApp());
}

class TravelDeskApp extends StatelessWidget {
  const TravelDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel Desk',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      home: const Gate(),
    );
  }
}

/// Decides between create-account, login and the app, and auto-locks the app
/// after it has been in the background for [lockAfter].
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  static const lockAfter = Duration(minutes: 3);
  bool? _hasAccount;
  bool _unlocked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final has = await AuthService.hasAccount();
    if (mounted) setState(() => _hasAccount = has);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = _pausedAt;
      _pausedAt = null;
      if (_unlocked && p != null && DateTime.now().difference(p) > lockAfter) {
        lock();
      }
    }
  }

  void lock() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    DataStore.instance.unload();
    if (mounted) setState(() => _unlocked = false);
  }

  Future<void> _onUnlocked() async {
    await DataStore.instance.load();
    if (mounted) {
      setState(() {
        _hasAccount = true;
        _unlocked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAccount == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_unlocked) {
      return LoginScreen(
        createMode: !_hasAccount!,
        onUnlocked: _onUnlocked,
      );
    }
    return HomeScreen(onLock: lock);
  }
}
