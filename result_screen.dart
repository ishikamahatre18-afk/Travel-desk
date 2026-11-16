import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/live_api.dart';
import '../services/message_composer.dart';
import '../services/planner.dart';
import '../theme.dart';
import '../widgets.dart';

class ResultScreen extends StatefulWidget {
  final Inquiry inquiry;
  const ResultScreen({super.key, required this.inquiry});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _store = DataStore.instance;
  final _text = TextEditingController();
  late final Destination _dest;
  late final QuoteResult _result;
  Tone _tone = Tone.friendly;
  bool _breakdown = false;
  bool _live = true;
  bool _loadingLive = false;
  String? _weather;
  String? _fxLine;

  @override
  void initState() {
    super.initState();
    _dest = _store.destById(widget.inquiry.destinationId)!;
    _result = Planner.build(
      q: widget.inquiry,
      profile: _store.profile,
      dest: _dest,
      rates: _store.transports,
    );
    _recompose();
    if (_result.ok) _fetchLive();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _recompose() {
    _text.text = MessageComposer.compose(
      q: widget.inquiry,
      profile: _store.profile,
      dest: _dest,
      r: _result,
      tone: _tone,
      showBreakdown: _breakdown,
      weather: _live ? _weather : null,
      fxLine: _live ? _fxLine : null,
    );
  }

  Future<void> _fetchLive() async {
    setState(() => _loadingLive = true);
    final q = widget.inquiry;
    final results = await Future.wait<String?>([
      LiveApi.weather(_dest.name, q.start, q.end),
      q.clientCurrency.isEmpty
          ? Future<String?>.value(null)
          : LiveApi.fxLine(_store.profile.currency, q.clientCurrency, _result.total),
    ]);
    if (!mounted) return;
    setState(() {
      _weather = results[0];
      _fxLine = results[1];
      _loadingLive = false;
    });
    _recompose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied. Ready to paste.')));
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_text.text)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp. Use Copy instead.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final profile = _store.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          for (final e in r.errors) NoticeCard(text: e, error: true),
          for (final w in r.warnings) NoticeCard(text: w),
          if (r.ok) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppTheme.teal, Color(0xFF4DB8A8)]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Package total',
                        style: TextStyle(color: Colors.white70)),
                    Text(MessageComposer.money(profile, r.total),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Per person', style: TextStyle(color: Colors.white70)),
                  Text(MessageComposer.money(profile, r.perPerson),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            gap(10),
            SectionCard(
              title: 'Your margin (private)',
              icon: Icons.visibility_off_outlined,
              child: Column(children: [
                for (final l in r.lines) _row(l.label, MessageComposer.money(profile, l.amount)),
                const Divider(),
                _row('Cost subtotal', MessageComposer.money(profile, r.subtotal)),
                _row('Markup (${_n(profile.markupPct)}%)',
                    MessageComposer.money(profile, r.markup)),
                _row('Tax (${_n(profile.gstPct)}%)', MessageComposer.money(profile, r.tax)),
              ]),
            ),
            gap(10),
            SegmentedButton<Tone>(
              segments: const [
                ButtonSegment(value: Tone.friendly, label: Text('Friendly')),
                ButtonSegment(value: Tone.formal, label: Text('Formal')),
              ],
              selected: {_tone},
              onSelectionChanged: (s) {
                setState(() => _tone = s.first);
                _recompose();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show price breakdown to client'),
              value: _breakdown,
              onChanged: (v) {
                setState(() => _breakdown = v);
                _recompose();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add live weather & currency (online)'),
              subtitle: _loadingLive
                  ? const Text('Checking…')
                  : Text(_weather == null && _fxLine == null
                      ? 'Nothing available right now'
                      : 'Added when available'),
              value: _live,
              onChanged: (v) {
                setState(() => _live = v);
                _recompose();
              },
            ),
            gap(6),
            const Text('Message (you can edit before copying)',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink)),
            gap(8),
            TextField(
              controller: _text,
              minLines: 12,
              maxLines: null,
              style: const TextStyle(height: 1.4),
            ),
          ],
        ],
      ),
      bottomNavigationBar: r.ok
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _whatsapp,
                        icon: const Icon(Icons.send),
                        label: const Text('WhatsApp')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy')),
                  ),
                ]),
              ),
            )
          : null,
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(a)),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
