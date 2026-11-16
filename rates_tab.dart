import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editors.dart';

class RatesTab extends StatefulWidget {
  const RatesTab({super.key});

  @override
  State<RatesTab> createState() => _RatesTabState();
}

class _RatesTabState extends State<RatesTab> {
  final _store = DataStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_r);
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_r);
    super.dispose();
  }

  Future<bool> _confirm(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete?'),
        content: Text(what),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _loadSamples() async {
    final goa = Destination(
      id: newId(),
      name: 'Goa (SAMPLE)',
      country: 'India',
      hotelBudget: 2500,
      hotelStandard: 4500,
      hotelLuxury: 9000,
      mealsPerDay: 800,
      activitiesPerDay: 600,
      localTransportPerDay: 400,
      peakMonths: [11, 12, 1],
      peakSurchargePct: 30,
      highlights: ['Beach day', 'Old Goa churches', 'Sunset cruise'],
    );
    _store.destinations.add(goa);
    _store.transports.add(TransportRate(
      id: '${newId()}1',
      from: 'Delhi',
      destinationId: goa.id,
      mode: TravelMode.flight,
      pricePerPerson: 6000,
      hours: 2.5,
    ));
    await _store.save();
  }

  @override
  Widget build(BuildContext context) {
    final dests = _store.destinations;
    final trans = _store.transports;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (dests.isEmpty && trans.isEmpty) ...[
          const NoticeCard(
              text: 'Add a destination, then add a transport route to it. '
                  'Or load clearly-labelled SAMPLE data to try the app.'),
          OutlinedButton(onPressed: _loadSamples, child: const Text('Load sample data')),
          gap(),
        ],
        _header('Destinations', () async {
          await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DestinationEditor()));
        }),
        for (final d in dests)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${d.country.isEmpty ? "" : "${d.country} · "}Hotel from ₹/night: '
                    '${[d.hotelBudget, d.hotelStandard, d.hotelLuxury].where((x) => x > 0).fold<double?>(null, (m, x) => m == null || x < m ? x : m)?.round() ?? "-"}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DestinationEditor(existing: d))),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await _confirm(
                        'Delete ${d.name} and its transport routes?')) {
                      _store.transports.removeWhere((t) => t.destinationId == d.id);
                      _store.destinations.removeWhere((x) => x.id == d.id);
                      await _store.save();
                    }
                  },
                ),
              ),
            ),
          ),
        gap(10),
        _header('Transport routes', () async {
          if (dests.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add a destination first.')));
            return;
          }
          await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TransportEditor()));
        }),
        for (final t in trans)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(t.mode == TravelMode.flight
                    ? Icons.flight
                    : t.mode == TravelMode.ship
                        ? Icons.directions_boat
                        : Icons.directions_bus),
                title: Text('${t.from} → ${_store.destById(t.destinationId)?.name ?? "?"}'),
                subtitle: Text('${t.mode.label} · ₹${t.pricePerPerson.round()} per person, one way'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TransportEditor(existing: t))),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await _confirm('Delete this route?')) {
                      _store.transports.removeWhere((x) => x.id == t.id);
                      await _store.save();
                    }
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(String title, VoidCallback onAdd) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink))),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ]),
      );
}
