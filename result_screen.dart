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
  final _priceC = TextEditingController();
  final _hoursC = TextEditingController();
  final _hotelC = TextEditingController();
  late Destination _dest;
  late QuoteResult _result;
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
    _compute();
    if (_result.ok) _fetchLive();
  }

  @override
  void dispose() {
    _text.dispose();
    _priceC.dispose();
    _hoursC.dispose();
    _hotelC.dispose();
    super.dispose();
  }

  void _compute() {
    _result = Planner.build(
      q: widget.inquiry,
      profile: _store.profile,
      dest: _dest,
      rates: _store.transports,
    );
    _recompose();
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

  void _msg(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _msg('Could not open the browser.');
  }

  Future<void> _checkTransport() {
    final q = widget.inquiry;
    return _open(LiveLinks.transport(
      mode: q.mode,
      from: q.origin,
      to: _dest.name,
      start: q.start,
      end: q.end,
      roundTrip: q.roundTrip,
    ));
  }

  Future<void> _checkHotel() {
    final q = widget.inquiry;
    final rooms = q.rooms ?? (q.adults / 2).ceil().clamp(1, 1000);
    return _open(LiveLinks.hotel(
      place: _dest.name,
      start: q.start,
      end: q.end,
      adults: q.adults,
      children: q.children,
      rooms: rooms,
    ));
  }

  Future<void> _saveMissing() async {
    final r = _result;
    final q = widget.inquiry;
    double? price;
    double? hotel;
    var hours = 0.0;
    if (r.needsRate) {
      price = parseNum(_priceC.text);
      if (price == null || price <= 0) return _msg('Enter the transport price.');
      if (_hoursC.text.trim().isNotEmpty) {
        final h = parseNum(_hoursC.text);
        if (h == null || h < 0) return _msg('Enter valid journey hours.');
        hours = h;
      }
    }
    if (r.needsHotel) {
      hotel = parseNum(_hotelC.text);
      if (hotel == null || hotel <= 0) return _msg('Enter the hotel price.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (price != null) {
      TransportRate? existing;
      for (final t in _store.transports) {
        if (t.mode == q.mode &&
            t.destinationId == _dest.id &&
            t.from.trim().toLowerCase() == q.origin.trim().toLowerCase()) {
          existing = t;
          break;
        }
      }
      if (existing != null) {
        existing.pricePerPerson = price;
        existing.hours = hours;
        existing.updatedAt = now;
      } else {
        _store.transports.add(TransportRate(
          id: newId(),
          from: q.origin.trim(),
          destinationId: _dest.id,
          mode: q.mode,
          pricePerPerson: price,
          hours: hours,
          updatedAt: now,
        ));
      }
    }
    if (hotel != null) {
      switch (q.tier) {
        case HotelTier.budget:
          _dest.hotelBudget = hotel;
        case HotelTier.standard:
          _dest.hotelStandard = hotel;
        case HotelTier.luxury:
          _dest.hotelLuxury = hotel;
      }
      _dest.hotelUpdatedAt = now;
    }
    await _store.save();
    if (!mounted) return;
    _priceC.clear();
    _hoursC.clear();
    _hotelC.clear();
    setState(_compute);
    if (_result.ok) {
      _msg('Saved. This price is now remembered.');
      _fetchLive();
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (!mounted) return;
    _msg('Copied. Ready to paste.');
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_text.text)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _msg('Could not open WhatsApp. Use Copy instead.');
  }

  Widget _missingPanel() {
    final r = _result;
    final q = widget.inquiry;
    final cur = _store.profile.currency;
    return SectionCard(
      title: 'Add the missing price',
      icon: Icons.add_card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Tap a check button, read the price in your browser, then type it here. '
          'It is saved with today\'s date, so you only do this once per route.',
          style: TextStyle(color: Colors.black54),
        ),
        gap(12),
        if (r.needsRate) ...[
          OutlinedButton.icon(
            onPressed: _checkTransport,
            icon: const Icon(Icons.open_in_new),
            label: Text('Check live ${q.mode.label.toLowerCase()} price'),
          ),
          gap(10),
          TextField(
            controller: _priceC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: '${q.mode.label} price per person, one way ($cur)'),
          ),
          gap(10),
          TextField(
            controller: _hoursC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Journey hours (optional)'),
          ),
          gap(14),
        ],
        if (r.needsHotel) ...[
          OutlinedButton.icon(
            onPressed: _checkHotel,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Check live hotel price'),
          ),
          gap(10),
          TextField(
            controller: _hotelC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: '${q.tier.label} hotel, per room per night ($cur)'),
          ),
          gap(14),
        ],
        const Text(
          'Privacy: the browser link contains only city names, dates and '
          'traveller counts. No client name, agency detail or rate is sent.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        gap(12),
        FilledButton(
            onPressed: _saveMissing, child: const Text('Save price & build plan')),
      ]),
    );
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
          if (!r.ok && (r.needsRate || r.needsHotel)) _missingPanel(),
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
