import 'dart:math';

import '../data/cities.dart';
import '../data/iata.dart';
import '../models.dart';
import 'estimator.dart';

class FareOffer {
  final String carrier;
  final String flightNo;
  final String departTime; // HH:mm
  final String arriveTime; // HH:mm, may end with " +1"
  final int durationMin;
  final int stops;
  final double pricePerAdult; // one way, in [FareSearchResult.currency]
  const FareOffer({
    required this.carrier,
    required this.flightNo,
    required this.departTime,
    required this.arriveTime,
    required this.durationMin,
    required this.stops,
    required this.pricePerAdult,
  });
}

class FareSearchResult {
  final String provider;
  final bool demo;
  final String currency;
  final List<FareOffer> offers; // cheapest first
  final String? note;
  const FareSearchResult({
    required this.provider,
    required this.demo,
    this.currency = 'INR',
    this.offers = const [],
    this.note,
  });

  FareOffer? get cheapest => offers.isEmpty ? null : offers.first;
}

/// A source of flight fares. The chatbot only talks to this interface, so a
/// live provider can replace the demo one without touching the chat code.
abstract class FlightFareProvider {
  String get name;
  bool get isDemo;
  Future<FareSearchResult> search({
    required City from,
    required City to,
    required DateTime date,
    required int adults,
    DateTime? today,
  });
}

/// Demo fare feed. Behaves like a remote API (asynchronous, with a short
/// delay, returning structured offers) but generates SIMULATED fares from
/// the offline estimator, adjusted for day of week, how soon the flight is,
/// and season. Carriers are fictional on purpose, so nothing here can be
/// mistaken for a real airline's price. The same search always gives the
/// same result.
class DemoFlightApi implements FlightFareProvider {
  final Duration latency;
  const DemoFlightApi({this.latency = const Duration(milliseconds: 700)});

  @override
  String get name => 'Demo fare feed';

  @override
  bool get isDemo => true;

  static const _carriers = <_Carrier>[
    _Carrier('BudgetWing Demo', 'BW', 0.80, true),
    _Carrier('Demo Air', 'DA', 0.88, true),
    _Carrier('Skyline Demo', 'SD', 1.08, false),
    _Carrier('Demo Jet Premium', 'DJ', 1.35, false),
  ];

  static int _seed(String s) {
    var h = 0x811C9DC5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }

  static double _dayFactor(DateTime d) {
    switch (d.weekday) {
      case DateTime.friday:
      case DateTime.sunday:
        return 1.12;
      case DateTime.saturday:
        return 1.05;
      case DateTime.tuesday:
      case DateTime.wednesday:
        return 0.92;
      default:
        return 1.0;
    }
  }

  static double _advanceFactor(int days) {
    if (days <= 2) return 1.5;
    if (days <= 7) return 1.3;
    if (days <= 14) return 1.15;
    if (days <= 30) return 1.0;
    if (days <= 60) return 0.93;
    return 0.9;
  }

  static double _seasonFactor(int month) {
    const m = {12: 1.18, 5: 1.12, 6: 1.10, 10: 1.10, 11: 1.08, 1: 1.05};
    return m[month] ?? 1.0;
  }

  static String _hm(int minutes) {
    final day = minutes ~/ 1440;
    final m = minutes % 1440;
    final s =
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return day > 0 ? '$s +$day' : s;
  }

  @override
  Future<FareSearchResult> search({
    required City from,
    required City to,
    required DateTime date,
    required int adults,
    DateTime? today,
  }) async {
    await Future<void>.delayed(latency);
    final base = Estimator.transport(
      from: from,
      to: to,
      mode: TravelMode.flight,
      fromLabel: from.name,
      destId: 'demo',
    );
    if (base == null) {
      return FareSearchResult(
        provider: name,
        demo: true,
        note: 'No flights found between ${from.name} and ${to.name}. '
            'They may be too close together for a flight.',
      );
    }

    final now = today ?? DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final advance = day.difference(t0).inDays;
    final km = Estimator.km(from, to);
    final longHaul = km > 3500;
    final rnd = Random(_seed('${from.name}|${to.name}|${day.year}-${day.month}-${day.day}'));
    final common = base.pricePerPerson *
        _dayFactor(day) *
        _advanceFactor(advance) *
        _seasonFactor(day.month);
    final baseMinutes = (base.hours * 60).round();

    final hours = <int>[6, 9, 13, 17, 21]..shuffle(rnd);
    final offers = <FareOffer>[];
    for (var i = 0; i < _carriers.length; i++) {
      final c = _carriers[i];
      final stops = (longHaul && c.cheap) ? 1 : 0;
      final stopFactor = stops == 1 ? 0.84 : 1.0;
      final price = (common * c.factor * stopFactor * (0.96 + rnd.nextDouble() * 0.08) / 10)
              .round() *
          10.0;
      final dep = hours[i] * 60 + (rnd.nextInt(4) * 15);
      final dur = baseMinutes + stops * (150 + rnd.nextInt(90));
      offers.add(FareOffer(
        carrier: c.name,
        flightNo: '${c.code} ${100 + rnd.nextInt(800)}',
        departTime: _hm(dep),
        arriveTime: _hm(dep + dur),
        durationMin: dur,
        stops: stops,
        pricePerAdult: price,
      ));
    }
    offers.sort((a, b) => a.pricePerAdult.compareTo(b.pricePerAdult));

    return FareSearchResult(
      provider: name,
      demo: true,
      offers: offers,
      note: '${airportFor(from.name)} to ${airportFor(to.name)}',
    );
  }
}

class _Carrier {
  final String name;
  final String code;
  final double factor;
  final bool cheap;
  const _Carrier(this.name, this.code, this.factor, this.cheap);
}

/// The provider the chatbot uses. Swap this for a live provider later.
class FlightFareService {
  static FlightFareProvider provider() => const DemoFlightApi();
}
