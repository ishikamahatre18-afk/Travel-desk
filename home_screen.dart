import 'package:flutter/material.dart';

import 'quote_tab.dart';
import 'rates_tab.dart';
import 'settings_tab.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onLock;
  const HomeScreen({super.key, required this.onLock});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      QuoteTab(onGoToRates: () => setState(() => _tab = 1)),
      const RatesTab(),
      SettingsTab(onLock: widget.onLock),
    ];
    const titles = ['New quote', 'Rates', 'Settings'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Lock now',
            icon: const Icon(Icons.lock_outline),
            onPressed: widget.onLock,
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'Quote'),
          NavigationDestination(
              icon: Icon(Icons.price_change_outlined),
              selectedIcon: Icon(Icons.price_change),
              label: 'Rates'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
