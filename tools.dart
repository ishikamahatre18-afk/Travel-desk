import 'package:intl/intl.dart';

import '../chat/chat_models.dart';
import '../data/cities.dart';
import '../models.dart';
import '../services/estimator.dart';
import '../services/flight_fares.dart';
import '../services/hotel_rates.dart';
import '../services/live_api.dart';
import '../services/message_composer.dart';
import '../services/planner.dart';
import '../services/resolver.dart';

class ToolOutput {
  /// What the language model gets to read.
  final String result;

  /// What the owner sees (cards, messages, actions). Prices shown here come
  /// straight from the planner or the rate feeds, never from the model.
  final List<BotMessage> show;
  const ToolOutput(this.result, [this.show = const []]);
  factory ToolOutput.error(String m) => ToolOutput('ERROR: $m');
}

/// Every operation the assistant can perform. All of it is ordinary Dart that
/// runs on the phone: the language model decides WHICH tool to call and with
/// what, and these functions do the exact work (prices, saving, settings).
class ToolBox {
  ToolBox({
    required this.store,
    FlightFareProvider? fares,
    HotelRateProvider? hotels,
    DateTime Function()? clock,
  })  : fares = fares ?? FlightFareService.provider(),
        hotels = hotels ?? HotelService.provider(),
        _clock = clock ?? DateTime.now;

  final DataStore store;
  final FlightFareProvider fares;
  final HotelRateProvider hotels;
  final DateTime Function() _clock;

  String? _lastMessage;

  DateTime get today {
    final n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  static final DateFormat _df = DateFormat('d MMM yyyy');
  String _money(double v) => MessageComposer.money(store.profile, v);

  // ---------------------------------------------------------------- parsing

  static String _str(dynamic v) => (v ?? '').toString().trim();

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(RegExp(r'[,₹\s]'), ''));
  }

  static int? _int(dynamic v) => _num(v)?.round();

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  static bool? _bool(dynamic v) {
    if (v is bool) return v;
    final s = _str(v).toLowerCase();
    if (s == 'true' || s == 'yes') return true;
    if (s == 'false' || s == 'no') return false;
    return null;
  }

  static DateTime? _date(dynamic v) {
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(_str(v));
    if (m == null) return null;
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    final dt = DateTime(y, mo, d);
    return (dt.month == mo && dt.day == d) ? dt : null;
  }

  static TravelMode _mode(dynamic v) {
    final s = _str(v).toLowerCase();
    if (s.contains('road') || s.contains('bus') || s.contains('car') || s.contains('cab') || s.contains('train')) {
      return TravelMode.road;
    }
    if (s.contains('ship') || s.contains('cruise') || s.contains('ferry')) return TravelMode.ship;
    return TravelMode.flight;
  }

  static HotelTier _tier(dynamic v) {
    final s = _str(v).toLowerCase();
    if (s.contains('lux') || s.contains('5') || s.contains('4')) return HotelTier.luxury;
    if (s.contains('bud') || s.contains('cheap') || s.contains('2')) return HotelTier.budget;
    return HotelTier.standard;
  }

  static String _titleCase(String s) => s
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  /// The canonical spelling of a place the owner mentioned.
  String _place(String raw) {
    final low = raw.trim().toLowerCase();
    for (final d in store.destinations) {
      if (d.name.trim().toLowerCase() == low) return d.name;
    }
    for (final t in store.transports) {
      if (t.from.trim().toLowerCase() == low) return t.from;
    }
    return findCity(raw)?.name ?? _titleCase(raw);
  }

  String _destIdFor(String name) {
    for (final d in store.destinations) {
      if (d.name.trim().toLowerCase() == name.trim().toLowerCase()) return d.id;
    }
    final c = findCity(name);
    return c != null ? 'est:${c.name}' : 'new:$name';
  }

  // ------------------------------------------------------------------ entry

  Future<ToolOutput> run(String name, Map<String, dynamic> a) async {
    try {
      switch (name) {
        case 'search_flights':
          return await _searchFlights(a);
        case 'search_hotels':
          return await _searchHotels(a);
        case 'make_quote':
          return await _makeQuote(a);
        case 'save_price':
          return await _savePrice(a);
        case 'list_rates':
          return _listRates();
        case 'delete_rate':
          return await _deleteRate(a);
        case 'set_setting':
          return await _setSetting(a);
        case 'remember':
          return await _remember(a);
        case 'forget_note':
          return await _forgetNote(a);
        case 'share_message':
          return _share(a);
        case 'open_live_check':
          return _liveCheck(a);
        case 'account':
          return _account(a);
        default:
          return ToolOutput.error('unknown tool "$name". Available: search_flights, search_hotels, '
              'make_quote, save_price, list_rates, delete_rate, set_setting, remember, forget_note, '
              'share_message, open_live_check, account.');
      }
    } catch (e) {
      return ToolOutput.error('the tool failed ($e). Nothing was changed.');
    }
  }

  // ---------------------------------------------------------------- flights

  Future<ToolOutput> _searchFlights(Map<String, dynamic> a) async {
    final from = _str(a['from']), to = _str(a['to']);
    final date = _date(a['date']);
    if (from.isEmpty || to.isEmpty) return ToolOutput.error('"from" and "to" cities are required.');
    if (date == null) return ToolOutput.error('"date" is required as YYYY-MM-DD.');
    if (date.isBefore(today)) return ToolOutput.error('that date is in the past. Today is ${_df.format(today)}.');
    final fc = findCity(from), tc = findCity(to);
    if (fc == null || tc == null) {
      return ToolOutput.error('no airport data for "${fc == null ? from : to}". Ask the owner for the fare and '
          'use save_price.');
    }
    if (store.profile.currency.toUpperCase() != 'INR') {
      return ToolOutput.error('the fare feed is in INR but the agency currency is ${store.profile.currency}.');
    }
    final adults = _clampInt(_int(a['adults']) ?? 1, 1, 9);
    final ret = _date(a['return_date']);

    final out = await fares.search(from: fc, to: tc, date: date, adults: adults, today: today);
    final show = <BotMessage>[];
    final buf = StringBuffer();
    if (out.offers.isEmpty) return ToolOutput(out.note ?? 'No fares found.');
    show.add(BotMessage('', attachment: _fareCard(out, '${fc.name} → ${tc.name}', date)));
    buf.writeln('FARES ${fc.name}->${tc.name} ${_df.format(date)} (per adult, one way, ${out.demo ? 'DEMO simulated data' : out.provider}):');
    for (var i = 0; i < out.offers.length && i < 6; i++) {
      final o = out.offers[i];
      buf.writeln('${i + 1}. ${o.carrier} ${o.flightNo} ${o.departTime}-${o.arriveTime} '
          '${o.stops == 0 ? 'non-stop' : '${o.stops} stop'} ${o.pricePerAdult.round()}');
    }
    if (ret != null && ret.isAfter(date)) {
      final back = await fares.search(from: tc, to: fc, date: ret, adults: adults, today: today);
      if (back.offers.isNotEmpty) {
        show.add(BotMessage('', attachment: _fareCard(back, '${tc.name} → ${fc.name}', ret)));
        buf.writeln('RETURN ${tc.name}->${fc.name} ${_df.format(ret)}: cheapest ${back.offers.first.pricePerAdult.round()} '
            '(${back.offers.first.carrier})');
      }
    }
    buf.write('These fares are ${out.demo ? 'SIMULATED demo prices, say so' : 'from ${out.provider}'}. '
        'Cards are already shown. To price a trip with a fare, call make_quote with '
        'transport_price_per_person set to the one-way price per person.');
    return ToolOutput(buf.toString(), show);
  }

  FareCard _fareCard(FareSearchResult res, String title, DateTime date) {
    String dur(int m) => '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
    return FareCard(
      title: title,
      subtitle: '${_df.format(date)} · ${res.note ?? ''}',
      footnote: res.demo
          ? 'DEMO DATA: simulated fares from "${res.provider}", not real prices.'
          : 'Source: ${res.provider}',
      demo: res.demo,
      rows: [
        for (var i = 0; i < res.offers.length; i++)
          FareRow(
            index: i + 1,
            airline: '${res.offers[i].carrier} · ${res.offers[i].flightNo}',
            times: '${res.offers[i].departTime} → ${res.offers[i].arriveTime}',
            meta: '${dur(res.offers[i].durationMin)} · '
                '${res.offers[i].stops == 0 ? 'Non-stop' : '${res.offers[i].stops} stop'}',
            price: _money(res.offers[i].pricePerAdult),
            cheapest: i == 0,
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- hotels

  Future<ToolOutput> _searchHotels(Map<String, dynamic> a) async {
    final city = _str(a['city']);
    final cin = _date(a['check_in']), cout = _date(a['check_out']);
    if (city.isEmpty) return ToolOutput.error('"city" is required.');
    if (cin == null || cout == null) return ToolOutput.error('"check_in" and "check_out" are required as YYYY-MM-DD.');
    if (!cout.isAfter(cin)) return ToolOutput.error('check_out must be after check_in.');
    if (cin.isBefore(today)) return ToolOutput.error('check_in is in the past. Today is ${_df.format(today)}.');
    final c = findCity(city);
    final rooms = _clampInt(_int(a['rooms']) ?? 1, 1, 20);
    final adults = _clampInt(_int(a['adults']) ?? 2, 1, 60);
    final buf = StringBuffer();
    final show = <BotMessage>[];

    // The owner's own saved rate always comes first.
    final name = _place(city);
    for (final d in store.destinations) {
      if (d.name.toLowerCase() == name.toLowerCase() && d.source == 'owner') {
        buf.writeln('OWNER SAVED RATES for ${d.name} (per room per night): '
            'budget ${d.hotelBudget > 0 ? d.hotelBudget.round() : 'n/a'}, '
            'standard ${d.hotelStandard > 0 ? d.hotelStandard.round() : 'n/a'}, '
            'luxury ${d.hotelLuxury > 0 ? d.hotelLuxury.round() : 'n/a'}.');
      }
    }
    if (c == null) {
      buf.write('No hotel feed data for "$city". Use the owner\'s saved rate, or ask the owner and use save_price.');
      return ToolOutput(buf.toString());
    }
    if (store.profile.currency.toUpperCase() != 'INR') {
      return ToolOutput.error('the hotel feed is in INR but the agency currency is ${store.profile.currency}.');
    }
    final res = await hotels.search(city: c, checkIn: cin, checkOut: cout, rooms: rooms, adults: adults, today: today);
    if (res.offers.isEmpty) return ToolOutput(res.note ?? 'No hotels found.');
    final cheapest = res.offers.first.pricePerNight;
    show.add(BotMessage('',
        attachment: HotelCard(
          title: 'Hotels in ${c.name}',
          subtitle: '${_df.format(cin)} – ${_df.format(cout)} · ${res.note ?? ''}',
          footnote: res.demo
              ? 'DEMO DATA: simulated rates from "${res.provider}", not real prices. Per room per night.'
              : 'Source: ${res.provider}. Per room per night.',
          demo: res.demo,
          rows: [
            for (final o in res.offers)
              HotelRow(
                name: o.name,
                meta: '${'★' * o.stars} · ${o.area}${o.breakfast ? ' · Breakfast' : ''}${o.freeCancel ? ' · Free cancellation' : ''}',
                price: _money(o.pricePerNight),
                cheapest: o.pricePerNight == cheapest,
              ),
          ],
        )));
    buf.writeln('HOTELS in ${c.name} ${_df.format(cin)}-${_df.format(cout)} per room per night '
        '(${res.demo ? 'DEMO simulated data' : res.provider}):');
    for (final o in res.offers) {
      buf.writeln('- ${o.name} ${o.stars} star ${o.pricePerNight.round()}');
    }
    buf.write('Cards are already shown. To price a trip with one, call make_quote with hotel_price_per_night.');
    return ToolOutput(buf.toString(), show);
  }

  // ------------------------------------------------------------------ quote

  Destination _workingDest(Inquiry q, String destName) {
    final d = Resolver.destination(_destIdFor(destName), q, store);
    return d ?? Destination(id: 'new:$destName', name: destName);
  }

  Future<ToolOutput> _makeQuote(Map<String, dynamic> a) async {
    final fromRaw = _str(a['from']), toRaw = _str(a['to']);
    if (toRaw.isEmpty) return ToolOutput.error('missing destination ("to").');
    if (fromRaw.isEmpty) return ToolOutput.error('missing departure city ("from").');
    final start = _date(a['start']);
    if (start == null) return ToolOutput.error('missing or invalid "start" date, use YYYY-MM-DD.');
    var end = _date(a['end']);
    final nights = _int(a['nights']);
    if (end == null && nights != null && nights >= 1) end = start.add(Duration(days: nights));
    if (end == null) return ToolOutput.error('missing "end" date (or "nights").');
    if (!end.isAfter(start)) return ToolOutput.error('"end" must be after "start".');
    if (start.isBefore(today)) return ToolOutput.error('the start date is in the past. Today is ${_df.format(today)}.');
    if (end.difference(start).inDays > 60) return ToolOutput.error('trips longer than 60 nights are not supported.');
    final adults = _int(a['adults']) ?? 2;
    final children = _int(a['children']) ?? 0;
    if (adults < 1 || adults > 60) return ToolOutput.error('adults must be 1 to 60.');
    if (children < 0 || children > 60) return ToolOutput.error('children must be 0 to 60.');

    final origin = _place(fromRaw);
    final dest = _place(toRaw);
    final mode = _mode(a['mode']);
    final tier = _tier(a['hotel_tier']);
    final q = Inquiry(
      clientName: _str(a['client']),
      origin: origin,
      destinationId: _destIdFor(dest),
      mode: mode,
      start: start,
      end: end,
      adults: adults,
      children: children,
      rooms: _int(a['rooms']) == null ? null : _clampInt(_int(a['rooms'])!, 1, 60),
      tier: tier,
      includeActivities: _bool(a['include_activities']) ?? true,
      roundTrip: _bool(a['round_trip']) ?? true,
      clientCurrency: '',
    );

    var d = _workingDest(q, dest);
    final hotelOverride = _num(a['hotel_price_per_night']);
    if (hotelOverride != null && hotelOverride >= 100) {
      d = Destination.fromJson(d.toJson());
      switch (tier) {
        case HotelTier.budget:
          d.hotelBudget = hotelOverride;
        case HotelTier.standard:
          d.hotelStandard = hotelOverride;
        case HotelTier.luxury:
          d.hotelLuxury = hotelOverride;
      }
      d.source = 'estimate'; // one-off figure, keeps the "indicative" label
    }
    var rates = Resolver.ratesFor(q, d, store);
    final tOverride = _num(a['transport_price_per_person']);
    if (tOverride != null && tOverride >= 100) {
      rates = [
        TransportRate(
          id: 'oneoff',
          from: origin,
          destinationId: d.id,
          mode: mode,
          pricePerPerson: tOverride,
          source: 'estimate',
        ),
        ...rates,
      ];
    }
    final r = Planner.build(q: q, profile: store.profile, dest: d, rates: rates, today: today);
    if (!r.ok) {
      final b = StringBuffer('CANNOT QUOTE YET: ${r.errors.join(' ')} ');
      if (r.needsRate) {
        b.write('No ${mode.label.toLowerCase()} price for $origin -> $dest is saved and none can be estimated. '
            '${mode == TravelMode.flight ? 'Call search_flights, or ask the owner for the fare. ' : 'Ask the owner for the price per person. '}');
      }
      if (r.needsHotel) b.write('No hotel price for $dest. Call search_hotels or ask the owner. ');
      return ToolOutput(b.toString().trim());
    }

    final tone = _str(a['tone']).toLowerCase().startsWith('form') ? Tone.formal : Tone.friendly;
    final text = MessageComposer.compose(
      q: q,
      profile: store.profile,
      dest: d,
      r: r,
      tone: tone,
      showBreakdown: _bool(a['breakdown']) ?? false,
      weather: null,
      fxLine: null,
      estimated: r.estimated,
      today: today,
    );
    _lastMessage = text;

    final pax = '$adults adult${adults == 1 ? '' : 's'}${children > 0 ? ', $children child${children == 1 ? '' : 'ren'}' : ''}';
    final card = QuoteCard(
      route: '$origin → $dest',
      dates: '${DateFormat('d MMM').format(start)} – ${_df.format(end)} · ${r.nights} night${r.nights == 1 ? '' : 's'}',
      travellers: '$pax · ${r.rooms} room${r.rooms == 1 ? '' : 's'}',
      total: _money(r.total),
      perPerson: _money(r.perPerson),
      estimated: r.estimated,
      notes: r.warnings,
    );
    final res = StringBuffer('QUOTE READY. Total ${_money(r.total)}, ${_money(r.perPerson)} per person, '
        '${r.nights} nights, ${r.rooms} rooms, ${mode.label.toLowerCase()}, ${tier.label.toLowerCase()} hotel. ');
    res.write(r.estimated
        ? 'Some prices are ESTIMATES (not the owner\'s saved prices), the client message says "indicative". '
            'Offer to save real prices if the owner corrects them. '
        : 'All prices are the owner\'s saved prices. ');
    if (tOverride != null || hotelOverride != null) res.write('One-off prices were used for this quote only and NOT saved. ');
    if (r.warnings.isNotEmpty) res.write('Notes: ${r.warnings.join(' | ')}. ');
    res.write('The quote card and the copy-ready client message are already shown. Do not repeat them.');
    return ToolOutput(res.toString(), [
      BotMessage('', attachment: card),
      BotMessage('', attachment: MessageCard(text)),
    ]);
  }

  // ----------------------------------------------------------- saved prices

  Destination _persistDest(String destName) {
    final id = _destIdFor(destName);
    final existing = store.destById(id);
    if (existing != null) return existing;
    final c = findCity(destName);
    final base = c != null ? Estimator.destination(c) : Destination(id: 'new', name: destName);
    final copy = Destination.fromJson(base.toJson())
      ..id = newId()
      ..name = destName;
    store.destinations.add(copy);
    return copy;
  }

  Future<ToolOutput> _savePrice(Map<String, dynamic> a) async {
    final kind = _str(a['kind']).toLowerCase();
    final amount = _num(a['amount']);
    if (amount == null || amount < 1) return ToolOutput.error('"amount" must be a positive number.');
    final now = _clock().millisecondsSinceEpoch;
    final destName = _place(_str(a['to']).isNotEmpty ? _str(a['to']) : _str(a['city']));
    if (destName.isEmpty) return ToolOutput.error('say which destination or city this price is for.');

    switch (kind) {
      case 'flight':
      case 'road':
      case 'ship':
      case 'bus':
      case 'train':
        final from = _str(a['from']);
        if (from.isEmpty) return ToolOutput.error('"from" city is required for a route price.');
        final mode = _mode(kind);
        final origin = _place(from);
        final dr = _persistDest(destName);
        TransportRate? ex;
        for (final t in store.transports) {
          if (t.mode == mode &&
              t.destinationId == dr.id &&
              t.from.trim().toLowerCase() == origin.toLowerCase()) {
            ex = t;
          }
        }
        if (ex != null) {
          ex
            ..pricePerPerson = amount
            ..updatedAt = now
            ..source = 'owner';
        } else {
          store.transports.add(TransportRate(
            id: newId(),
            from: origin,
            destinationId: dr.id,
            mode: mode,
            pricePerPerson: amount,
            hours: 0,
            updatedAt: now,
            source: 'owner',
          ));
        }
        await store.save();
        return ToolOutput('SAVED: ${mode.label} $origin -> ${dr.name} = ${_money(amount)} per person one way. '
            'It will be used in every future quote for this route.');
      case 'hotel':
        final htier = _tier(a['tier']);
        final dh = _persistDest(destName);
        switch (htier) {
          case HotelTier.budget:
            dh.hotelBudget = amount;
          case HotelTier.standard:
            dh.hotelStandard = amount;
          case HotelTier.luxury:
            dh.hotelLuxury = amount;
        }
        dh
          ..hotelUpdatedAt = now
          ..source = 'owner';
        await store.save();
        return ToolOutput('SAVED: ${htier.label} hotel in ${dh.name} = ${_money(amount)} per room per night.');
      case 'meals':
      case 'activities':
      case 'local_transport':
        final dm = _persistDest(destName);
        if (kind == 'meals') dm.mealsPerDay = amount;
        if (kind == 'activities') dm.activitiesPerDay = amount;
        if (kind == 'local_transport') dm.localTransportPerDay = amount;
        dm.source = 'owner';
        await store.save();
        return ToolOutput('SAVED: $kind in ${dm.name} = ${_money(amount)} per person per day.');
      default:
        return ToolOutput.error('kind must be one of flight, road, ship, hotel, meals, activities, local_transport.');
    }
  }

  ToolOutput _listRates() {
    final dests = store.destinations, routes = store.transports;
    if (dests.isEmpty && routes.isEmpty) {
      return const ToolOutput('The owner has no saved prices yet. Estimates are used until they save real ones.');
    }
    final b = StringBuffer('Your saved prices:\n');
    if (dests.isNotEmpty) {
      b.writeln('\nDestinations');
      for (final d in dests) {
        final h = [d.hotelBudget, d.hotelStandard, d.hotelLuxury].where((x) => x > 0).toList()..sort();
        b.writeln('• ${d.name}${d.source == 'estimate' ? ' (estimate)' : ''}: hotel from '
            '${h.isEmpty ? '-' : _money(h.first)}/night, meals ${_money(d.mealsPerDay)}/day');
      }
    }
    if (routes.isNotEmpty) {
      b.writeln('\nRoutes (per person, one way)');
      for (final t in routes) {
        b.writeln('• ${t.from} → ${store.destById(t.destinationId)?.name ?? '?'}, ${t.mode.label}: '
            '${_money(t.pricePerPerson)}${t.source == 'estimate' ? ' (estimate)' : ''}');
      }
    }
    return ToolOutput('The list of saved prices is already shown to the owner.', [BotMessage(b.toString().trimRight())]);
  }

  Future<ToolOutput> _deleteRate(Map<String, dynamic> a) async {
    final to = _str(a['to']).isNotEmpty ? _str(a['to']) : _str(a['city']);
    if (to.isEmpty) return ToolOutput.error('say which destination to delete.');
    final from = _str(a['from']);
    final name = _place(to);
    Destination? dest;
    for (final d in store.destinations) {
      if (d.name.toLowerCase() == name.toLowerCase()) dest = d;
    }
    if (dest == null) return ToolOutput('There is no saved destination called $name. Nothing to delete.');
    final routes = store.transports
        .where((t) =>
            t.destinationId == dest!.id &&
            (from.isEmpty || t.from.toLowerCase() == _place(from).toLowerCase()))
        .toList();
    final what = from.isEmpty
        ? '${dest.name} and its ${routes.length} saved route${routes.length == 1 ? '' : 's'}'
        : 'the saved ${routes.length} route${routes.length == 1 ? '' : 's'} ${_place(from)} -> ${dest.name}';
    if (_bool(a['confirmed']) != true) {
      return ToolOutput('NEEDS CONFIRMATION: ask the owner "Delete $what?" and wait for a clear yes. '
          'Only then call delete_rate again with confirmed true.');
    }
    final ids = routes.map((t) => t.id).toSet();
    store.transports.removeWhere((t) => ids.contains(t.id));
    if (from.isEmpty) store.destinations.removeWhere((d) => d.id == dest!.id);
    await store.save();
    return ToolOutput('DELETED: $what.');
  }

  // --------------------------------------------------------------- settings

  Future<ToolOutput> _setSetting(Map<String, dynamic> a) async {
    final name = _str(a['name']).toLowerCase();
    final raw = _str(a['value']);
    final p = store.profile;
    double? n() => _num(raw);
    String done;
    switch (name) {
      case 'markup':
        final v1 = n();
        if (v1 == null || v1 < 0 || v1 > 200) return ToolOutput.error('markup must be between 0 and 200.');
        p.markupPct = v1;
        done = 'markup $v1%';
      case 'tax':
      case 'gst':
        final v2 = n();
        if (v2 == null || v2 < 0 || v2 > 50) return ToolOutput.error('tax must be between 0 and 50.');
        p.gstPct = v2;
        done = 'tax $v2%';
      case 'child_discount':
        final v3 = n();
        if (v3 == null || v3 < 0 || v3 > 100) return ToolOutput.error('child discount must be between 0 and 100.');
        p.childDiscountPct = v3;
        done = 'child discount $v3%';
      case 'validity_days':
        final v4 = n()?.round();
        if (v4 == null || v4 < 1 || v4 > 60) return ToolOutput.error('validity must be 1 to 60 days.');
        p.validityDays = v4;
        done = 'quotes valid $v4 days';
      case 'currency':
        if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(raw)) return ToolOutput.error('currency must be a 3-letter code like INR.');
        p.currency = raw.toUpperCase();
        done = 'currency ${p.currency}';
      case 'phone':
        p.phone = raw;
        done = 'phone $raw';
      case 'agency_name':
        if (raw.isEmpty) return ToolOutput.error('the agency needs a name.');
        p.name = raw;
        done = 'agency name "$raw"';
      default:
        return ToolOutput.error('setting must be markup, tax, child_discount, validity_days, currency, phone or agency_name.');
    }
    await store.save();
    return ToolOutput('SAVED SETTING: $done.');
  }

  // ----------------------------------------------------------------- memory

  Future<ToolOutput> _remember(Map<String, dynamic> a) async {
    final note = _str(a['note']).replaceAll(RegExp(r'\s+'), ' ');
    if (note.isEmpty) return ToolOutput.error('"note" is empty.');
    if (note.length > 240) return ToolOutput.error('keep the note under 240 characters.');
    if (store.notes.contains(note)) return const ToolOutput('Already remembered.');
    if (store.notes.length >= 40) return ToolOutput.error('memory is full (40 notes). Ask the owner which note to forget.');
    store.notes.add(note);
    await store.save();
    return ToolOutput('REMEMBERED: "$note". It is stored encrypted in this account.');
  }

  Future<ToolOutput> _forgetNote(Map<String, dynamic> a) async {
    final text = _str(a['note']).toLowerCase();
    if (text.isEmpty) return ToolOutput.error('say which note to forget.');
    final hit = store.notes.where((n) => n.toLowerCase().contains(text)).toList();
    if (hit.isEmpty) return const ToolOutput('No remembered note matches that.');
    store.notes.removeWhere(hit.contains);
    await store.save();
    return ToolOutput('FORGOT ${hit.length} note${hit.length == 1 ? '' : 's'}.');
  }

  // ------------------------------------------------------- actions & links

  ToolOutput _share(Map<String, dynamic> a) {
    final t = _lastMessage;
    if (t == null) return ToolOutput.error('there is no quote message yet. Make a quote first.');
    final wa = _str(a['via']).toLowerCase().contains('whats');
    return ToolOutput(wa ? 'Opening WhatsApp with the message.' : 'Message copied to the clipboard.', [
      BotMessage('', action: ChatAction(wa ? ChatActionType.whatsapp : ChatActionType.copy, text: t)),
    ]);
  }

  ToolOutput _liveCheck(Map<String, dynamic> a) {
    final kind = _str(a['kind']).toLowerCase();
    final start = _date(a['start']), end = _date(a['end']) ?? start?.add(const Duration(days: 1));
    if (start == null || end == null) return ToolOutput.error('"start" is required as YYYY-MM-DD.');
    final adults = _clampInt(_int(a['adults']) ?? 2, 1, 60);
    final Uri uri;
    if (kind.contains('hotel')) {
      final city = _str(a['city']);
      if (city.isEmpty) return ToolOutput.error('"city" is required.');
      uri = LiveLinks.hotel(
          place: _place(city), start: start, end: end, adults: adults, children: 0, rooms: (adults / 2).ceil());
    } else {
      final from = _str(a['from']), to = _str(a['to']);
      if (from.isEmpty || to.isEmpty) return ToolOutput.error('"from" and "to" are required.');
      uri = LiveLinks.transport(
          mode: _mode(a['mode']),
          from: _place(from),
          to: _place(to),
          start: start,
          end: end,
          roundTrip: _bool(a['round_trip']) ?? true);
    }
    return ToolOutput(
        'Opening the browser for a live price check. Only city names, dates and traveller counts are in the link. '
        'Tell the owner to give you the price they see so you can save it with save_price.',
        [BotMessage('', action: ChatAction(ChatActionType.openLink, uri: uri))]);
  }

  ToolOutput _account(Map<String, dynamic> a) {
    final act = _str(a['action']).toLowerCase();
    final ChatActionType t;
    switch (act) {
      case 'change_password':
        t = ChatActionType.changePassword;
      case 'new_recovery_code':
        t = ChatActionType.newRecovery;
      case 'lock':
        t = ChatActionType.lock;
      case 'remove_account':
        t = ChatActionType.removeAccount;
      default:
        return ToolOutput.error('action must be change_password, new_recovery_code, lock or remove_account.');
    }
    return ToolOutput('The secure form is opening for the owner. Passwords are never typed into the chat.',
        [BotMessage('', action: ChatAction(t))]);
  }
}
