import 'package:flutter/material.dart';

import 'ai/brain.dart';
import 'models.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'services/account_service.dart';
import 'services/cloud_service.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Brain.initialize();
  } catch (_) {
    // The assistant setup panel reports any problem to the owner.
  }
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

/// Shows the login screen or the app, and locks again after the app has been
/// in the background for [lockAfter]. Locking wipes the keys from memory.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  static const lockAfter = Duration(minutes: 3);
  Session? _session;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      if (_session != null &&
          p != null &&
          DateTime.now().difference(p) > lockAfter) {
        lock();
      } else if (_session != null) {
        CloudService.instance.scheduleSync(delay: Duration.zero);
      }
    }
  }

  void lock() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    CloudService.instance.detach();
    DataStore.instance.unload();
    if (mounted) setState(() => _session = null);
  }

  Future<void> _onUnlocked(Session s) async {
    await DataStore.instance.load(s.account.id, s.dek);
    CloudService.instance.attach(s);
    if (mounted) setState(() => _session = s);
  }

  void _onSessionChanged(Session s) {
    setState(() => _session = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return LoginScreen(onUnlocked: _onUnlocked);
    }
    return ChatScreen(
      session: s,
      onLock: lock,
      onSessionChanged: _onSessionChanged,
    );
  }
}
