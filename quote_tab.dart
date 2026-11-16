import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/live_api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'result_screen.dart';

class QuoteTab extends StatefulWidget {
  final VoidCallback onGoToRates;
  const QuoteTab({super.key, required this.onGoToRates});

  @override
  State<QuoteTab> createState() => _QuoteTabState();
}

class _QuoteTabState extends State<QuoteTab> {
  final _store = DataStore.instance;
  final _client = TextEditingController();
  final _origin = TextEditingController();
  final _originFocus = FocusNode();
  String? _destId;
  TravelMode _mode = TravelMode.flight;
  DateTimeRange? _range;
  int _adults = 2;
  int _children = 0;
  int? _roomsOverride;
  HotelTier _tier = HotelTier.standard;
  bool _activities = true;
  bool _round = true;
  String _fx = '';

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
  }

  void _onStore() {
    if (!mounted) return;
    if (_destId != null && _store.destById(_destId!) == null) _destId = null;
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _client.dispose();
    _origin.dispose();
    _originFocus.dispose();
    super.dispose();
  }

  int get _autoRooms => (_adults / 2).ceil().clamp(1, 1000);

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final r = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      initialDateRange: _range,
      helpText: 'Select travel dates',
    );
    if (r != null) setState(() => _range = r);
  }

  void _submit() {
    String? problem;
    if (_destId == null) {
      problem = 'Choose a destination.';
    } else if (_origin.text.trim().isEmpty) {
      problem = 'Enter the departure city.';
    } else if (_range == null) {
      problem = 'Select the travel dates.';
    }
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final inquiry = Inquiry(
      clientName: _client.text,
      origin: _origin.text,
      destinationId: _destId!,
      mode: _mode,
      start: _range!.start,
      end: _range!.end,
      adults: _adults,
      children: _children,
      rooms: _roomsOverride,
      tier: _tier,
      includeActivities: _activities,
      roundTrip: _round,
      clientCurrency: _fx,
    );
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultScreen(inquiry: inquiry)));
  }

  @override
  Widget build(BuildContext context) {
    if (_store.destinations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.travel_explore, size: 56, color: AppTheme.teal),
            gap(12),
            const Text('Add your rates first',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            gap(6),
            const Text(
              'Quotes are built from your own destination and transport prices, '
              'so every number is yours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            gap(18),
            FilledButton(
                onPressed: widget.onGoToRates, child: const Text('Open Rates')),
          ]),
        ),
      );
    }

    final originOptions = _store.transports.map((t) => t.from.trim()).toSet().toList();
    final df = DateFormat('d MMM yyyy');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        SectionCard(
          title: 'Trip',
          icon: Icons.map_outlined,
          child: Column(children: [
            TextField(
              controller: _client,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Client name (optional)',
                  prefixIcon: Icon(Icons.person_outline)),
            ),
            gap(12),
            RawAutocomplete<String>(
              textEditingController: _origin,
              focusNode: _originFocus,
              optionsBuilder: (v) => originOptions.where(
                  (o) => o.toLowerCase().contains(v.text.trim().toLowerCase())),
              fieldViewBuilder: (c, ctrl, node, onSubmit) => TextField(
                controller: ctrl,
                focusNode: node,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Departing from',
                    prefixIcon: Icon(Icons.trip_origin)),
              ),
              optionsViewBuilder: (c, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 200, maxWidth: 360),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          ListTile(title: Text(o), onTap: () => onSelected(o)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            gap(12),
            DropdownButtonFormField<String>(
              value: _destId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Destination', prefixIcon: Icon(Icons.place_outlined)),
              items: [
                for (final d in _store.destinations)
                  DropdownMenuItem(
                      value: d.id,
                      child: Text(d.country.isEmpty ? d.name : '${d.name}, ${d.country}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _destId = v),
            ),
            gap(12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TravelMode>(
                segments: const [
                  ButtonSegment(
                      value: TravelMode.flight,
                      icon: Icon(Icons.flight),
                      label: Text('Flight')),
                  ButtonSegment(
                      value: TravelMode.ship,
                      icon: Icon(Icons.directions_boat),
                      label: Text('Ship')),
                  ButtonSegment(
                      value: TravelMode.road,
                      icon: Icon(Icons.directions_bus),
                      label: Text('Road')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
            gap(12),
            OutlinedButton.icon(
              onPressed: _pickDates,
              icon: const Icon(Icons.calendar_month),
              label: Text(_range == null
                  ? 'Select travel dates'
                  : '${df.format(_range!.start)}  →  ${df.format(_range!.end)}'),
            ),
          ]),
        ),
        gap(),
        SectionCard(
          title: 'Travellers & stay',
          icon: Icons.groups_2_outlined,
          child: Column(children: [
            CountStepper(
              label: 'Adults',
              value: _adults,
              min: 1,
              onChanged: (v) => setState(() => _adults = v),
            ),
            CountStepper(
              label: 'Children',
              value: _children,
              onChanged: (v) => setState(() => _children = v),
            ),
            CountStepper(
              label: _roomsOverride == null ? 'Rooms (auto)' : 'Rooms',
              value: _roomsOverride ?? _autoRooms,
              min: 1,
              max: 30,
              onChanged: (v) => setState(() => _roomsOverride = v),
            ),
            gap(8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<HotelTier>(
                segments: [
                  for (final t in HotelTier.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_tier},
                onSelectionChanged: (s) => setState(() => _tier = s.first),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Return journey'),
              value: _round,
              onChanged: (v) => setState(() => _round = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include sightseeing & activities'),
              value: _activities,
              onChanged: (v) => setState(() => _activities = v),
            ),
            DropdownButtonFormField<String>(
              value: _fx,
              decoration: const InputDecoration(
                  labelText: 'Also show approx. price in (online)'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not needed')),
                for (final c in LiveApi.supportedFx)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _fx = v ?? ''),
            ),
          ]),
        ),
        gap(20),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Create plan'),
        ),
      ],
    );
  }
}
