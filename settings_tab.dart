import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth_service.dart';
import '../widgets.dart';

class SettingsTab extends StatefulWidget {
  final VoidCallback onLock;
  const SettingsTab({super.key, required this.onLock});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _store = DataStore.instance;
  late final TextEditingController name, phone, currency, markup, gst, child, validity;

  String _f(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    final p = _store.profile;
    name = TextEditingController(text: p.name);
    phone = TextEditingController(text: p.phone);
    currency = TextEditingController(text: p.currency);
    markup = TextEditingController(text: _f(p.markupPct));
    gst = TextEditingController(text: _f(p.gstPct));
    child = TextEditingController(text: _f(p.childDiscountPct));
    validity = TextEditingController(text: p.validityDays.toString());
  }

  @override
  void dispose() {
    for (final c in [name, phone, currency, markup, gst, child, validity]) {
      c.dispose();
    }
    super.dispose();
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final mk = parseNum(markup.text);
    final tx = parseNum(gst.text);
    final cd = parseNum(child.text);
    final vd = int.tryParse(validity.text.trim());
    if (name.text.trim().isEmpty) return _msg('Enter the agency name.');
    if (mk == null || mk < 0 || mk > 200) return _msg('Markup must be between 0 and 200.');
    if (tx == null || tx < 0 || tx > 50) return _msg('Tax must be between 0 and 50.');
    if (cd == null || cd < 0 || cd > 100) return _msg('Child discount must be between 0 and 100.');
    if (vd == null || vd < 1 || vd > 60) return _msg('Validity must be 1 to 60 days.');
    final cur = currency.text.trim().toUpperCase();
    if (cur.length != 3) return _msg('Use a 3-letter currency code, e.g. INR.');
    _store.profile
      ..name = name.text.trim()
      ..phone = phone.text.trim()
      ..currency = cur
      ..markupPct = mk
      ..gstPct = tx
      ..childDiscountPct = cd
      ..validityDays = vd;
    await _store.save();
    _msg('Saved.');
  }

  Future<void> _changePassword() async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Change password'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: oldC, obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password')),
            gap(10),
            TextField(controller: newC, obscureText: true,
                decoration: const InputDecoration(labelText: 'New password')),
            if (err != null) ...[gap(10), NoticeCard(text: err!, error: true)],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final r = await AuthService.changePassword(oldC.text, newC.text);
                if (r == null) {
                  if (c.mounted) Navigator.pop(c);
                  _msg('Password changed.');
                } else {
                  setD(() => err = r);
                }
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    oldC.dispose();
    newC.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        SectionCard(title: 'Agency', icon: Icons.storefront_outlined, child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Agency name')),
          gap(12),
          TextField(controller: phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (shown in messages)')),
          gap(12),
          TextField(controller: currency, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Currency code (e.g. INR)')),
        ])),
        gap(),
        SectionCard(title: 'Pricing rules', icon: Icons.percent, child: Column(children: [
          TextField(controller: markup, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Your markup (%)')),
          gap(12),
          TextField(controller: gst, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tax / GST (%)')),
          gap(12),
          TextField(controller: child, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Child discount (%)')),
          gap(12),
          TextField(controller: validity, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quote validity (days)')),
        ])),
        gap(16),
        FilledButton(onPressed: _save, child: const Text('Save settings')),
        gap(),
        SectionCard(title: 'Security', icon: Icons.shield_outlined, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your login and all rates are stored encrypted on this phone '
                'using the Android Keystore. Nothing is sent to any server. '
                'The app locks after 3 minutes in the background.',
                style: TextStyle(color: Colors.black54)),
            gap(12),
            OutlinedButton.icon(
                onPressed: _changePassword,
                icon: const Icon(Icons.key),
                label: const Text('Change password')),
            gap(10),
            OutlinedButton.icon(
                onPressed: widget.onLock,
                icon: const Icon(Icons.lock),
                label: const Text('Lock now')),
          ],
        )),
      ],
    );
  }
}
