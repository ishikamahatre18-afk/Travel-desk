import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

TextField _num(TextEditingController c, String label, {String? hint}) => TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, helperText: hint),
    );

class DestinationEditor extends StatefulWidget {
  final Destination? existing;
  const DestinationEditor({super.key, this.existing});

  @override
  State<DestinationEditor> createState() => _DestinationEditorState();
}

class _DestinationEditorState extends State<DestinationEditor> {
  final _store = DataStore.instance;
  late final TextEditingController name, country, budget, standard, luxury, meals,
      acts, local, surcharge, visa, highlights;
  late Set<int> peak;

  String _f(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    name = TextEditingController(text: d?.name ?? '');
    country = TextEditingController(text: d?.country ?? '');
    budget = TextEditingController(text: _f(d?.hotelBudget ?? 0));
    standard = TextEditingController(text: _f(d?.hotelStandard ?? 0));
    luxury = TextEditingController(text: _f(d?.hotelLuxury ?? 0));
    meals = TextEditingController(text: _f(d?.mealsPerDay ?? 0));
    acts = TextEditingController(text: _f(d?.activitiesPerDay ?? 0));
    local = TextEditingController(text: _f(d?.localTransportPerDay ?? 0));
    surcharge = TextEditingController(text: _f(d?.peakSurchargePct ?? 0));
    visa = TextEditingController(text: d?.visaNote ?? '');
    highlights = TextEditingController(text: (d?.highlights ?? []).join('\n'));
    peak = {...(d?.peakMonths ?? <int>[])};
  }

  @override
  void dispose() {
    for (final c in [name, country, budget, standard, luxury, meals, acts, local, surcharge, visa, highlights]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final nums = {
      'Budget hotel': budget,
      'Standard hotel': standard,
      'Luxury hotel': luxury,
      'Meals': meals,
      'Activities': acts,
      'Local transport': local,
      'Peak supplement': surcharge,
    };
    for (final e in nums.entries) {
      final t = e.value.text.trim();
      if (t.isNotEmpty) {
        final v = parseNum(t);
        if (v == null || v < 0) {
          _msg('${e.key}: enter a valid number.');
          return;
        }
      }
    }
    if (name.text.trim().isEmpty) {
      _msg('Enter the destination name.');
      return;
    }
    final dup = _store.destinations.any((d) =>
        d.id != widget.existing?.id &&
        d.name.trim().toLowerCase() == name.text.trim().toLowerCase());
    if (dup) {
      _msg('A destination with this name already exists.');
      return;
    }
    if ((parseNum(budget.text) ?? 0) + (parseNum(standard.text) ?? 0) + (parseNum(luxury.text) ?? 0) <= 0) {
      _msg('Enter at least one hotel price.');
      return;
    }
    double n(TextEditingController c) => parseNum(c.text) ?? 0;
    final d = widget.existing ?? Destination(id: newId(), name: '');
    d
      ..name = name.text.trim()
      ..country = country.text.trim()
      ..hotelBudget = n(budget)
      ..hotelStandard = n(standard)
      ..hotelLuxury = n(luxury)
      ..mealsPerDay = n(meals)
      ..activitiesPerDay = n(acts)
      ..localTransportPerDay = n(local)
      ..peakSurchargePct = n(surcharge)
      ..visaNote = visa.text.trim()
      ..peakMonths = (peak.toList()..sort())
      ..highlights = highlights.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    if (widget.existing == null) _store.destinations.add(d);
    await _store.save();
    if (mounted) Navigator.pop(context);
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New destination' : 'Edit destination')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SectionCard(title: 'Place', child: Column(children: [
            TextField(controller: name, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Destination name')),
            gap(12),
            TextField(controller: country, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Country')),
          ])),
          gap(),
          SectionCard(title: 'Hotel, per room per night', child: Column(children: [
            _num(budget, 'Budget', hint: 'Leave empty if not offered'),
            gap(12),
            _num(standard, 'Standard'),
            gap(12),
            _num(luxury, 'Luxury'),
          ])),
          gap(),
          SectionCard(title: 'Per person, per day', child: Column(children: [
            _num(meals, 'Meals'),
            gap(12),
            _num(acts, 'Sightseeing & activities'),
            gap(12),
            _num(local, 'Local transport'),
          ])),
          gap(),
          SectionCard(title: 'Peak season', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (var m = 1; m <= 12; m++)
                FilterChip(
                  label: Text(_months[m - 1]),
                  selected: peak.contains(m),
                  onSelected: (s) => setState(() => s ? peak.add(m) : peak.remove(m)),
                ),
            ]),
            gap(12),
            _num(surcharge, 'Hotel supplement on peak nights (%)'),
          ])),
          gap(),
          SectionCard(title: 'Client-facing notes', child: Column(children: [
            TextField(controller: highlights, minLines: 3, maxLines: 8,
                decoration: const InputDecoration(
                    labelText: 'Highlights (one per line)',
                    helperText: 'Spread across the middle days of the plan')),
            gap(12),
            TextField(controller: visa, minLines: 2, maxLines: 5,
                decoration: const InputDecoration(labelText: 'Visa / documents note')),
          ])),
          gap(20),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

class TransportEditor extends StatefulWidget {
  final TransportRate? existing;
  const TransportEditor({super.key, this.existing});

  @override
  State<TransportEditor> createState() => _TransportEditorState();
}

class _TransportEditorState extends State<TransportEditor> {
  final _store = DataStore.instance;
  late final TextEditingController from, price, hours, notes;
  String? destId;
  TravelMode mode = TravelMode.flight;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    from = TextEditingController(text: t?.from ?? '');
    price = TextEditingController(
        text: t == null ? '' : (t.pricePerPerson == t.pricePerPerson.roundToDouble() ? t.pricePerPerson.toInt().toString() : t.pricePerPerson.toString()));
    hours = TextEditingController(text: t == null || t.hours == 0 ? '' : t.hours.toString());
    notes = TextEditingController(text: t?.notes ?? '');
    destId = t?.destinationId ?? (_store.destinations.isNotEmpty ? _store.destinations.first.id : null);
    mode = t?.mode ?? TravelMode.flight;
  }

  @override
  void dispose() {
    for (final c in [from, price, hours, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final p = parseNum(price.text);
    if (from.text.trim().isEmpty) return _msg('Enter the departure city.');
    if (destId == null) return _msg('Choose a destination.');
    if (p == null || p <= 0) return _msg('Enter a price greater than 0.');
    final h = hours.text.trim().isEmpty ? 0.0 : parseNum(hours.text);
    if (h == null || h < 0) return _msg('Enter valid hours.');
    final dup = _store.transports.any((t) =>
        t.id != widget.existing?.id &&
        t.mode == mode &&
        t.destinationId == destId &&
        t.from.trim().toLowerCase() == from.text.trim().toLowerCase());
    if (dup) return _msg('This route and mode already exists. Edit it instead.');
    final t = widget.existing ??
        TransportRate(id: newId(), from: '', destinationId: destId!, mode: mode, pricePerPerson: p);
    t
      ..from = from.text.trim()
      ..destinationId = destId!
      ..mode = mode
      ..pricePerPerson = p
      ..hours = h
      ..notes = notes.text.trim();
    if (widget.existing == null) _store.transports.add(t);
    await _store.save();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New route' : 'Edit route')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SectionCard(title: 'Route', child: Column(children: [
            TextField(controller: from, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Departing from')),
            gap(12),
            DropdownButtonFormField<String>(
              value: destId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Destination'),
              items: [for (final d in _store.destinations) DropdownMenuItem(value: d.id, child: Text(d.name))],
              onChanged: (v) => setState(() => destId = v),
            ),
            gap(12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TravelMode>(
                segments: [for (final m in TravelMode.values) ButtonSegment(value: m, label: Text(m.label))],
                selected: {mode},
                onSelectionChanged: (s) => setState(() => mode = s.first),
              ),
            ),
          ])),
          gap(),
          SectionCard(title: 'Price', child: Column(children: [
            _num(price, 'Price per person, one way'),
            gap(12),
            _num(hours, 'Journey time in hours (optional)'),
            gap(12),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes (private)')),
          ])),
          gap(20),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
