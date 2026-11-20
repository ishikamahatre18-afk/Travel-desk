import 'dart:math';

import '../data/cities.dart';
import '../models.dart';
import 'estimator.dart';

class HotelOffer {
  final String name;
  final int stars;
  final String area;
  final double pricePerNight; // per room, average over the stay
  final bool breakfast;
  final bool freeCancel;
  const HotelOffer({
    required this.name,
    required this.stars,
    required this.area,
    required this.pricePerNight,
    required this.breakfast,
    required this.freeCancel,
  });
}

class HotelSearchResult {
  final String provider;
  final bool demo;
  final String currency;
  final List<HotelOffer> offers;
  final String? note;
  const HotelSearchResult({
    required this.provider,
    required this.demo,
    required this.currency,
    required this.offers,
    this.note,
  });
}

/// Anything that can return hotel rates. Swap [HotelService.provider] for a
/// real feed later without touching the assistant.
abstract class HotelRateProvider {
  Future<HotelSearchResult> search({
    required City city,
    required DateTime checkIn,
    required DateTime checkOut,
    required int rooms,
    required int adults,
    required DateTime today,
  });
}

/// DEMO feed. The hotels are fictional and the prices are simulated from the
/// built-in cost levels, the season, weekends and how soon the stay is. The
/// same search always gives the same answer. It is labelled DEMO everywhere.
class DemoHotelApi implements HotelRateProvider {
  final Duration latency;
  const DemoHotelApi({this.latency = const Duration(milliseconds: 600)});

  static const _classes = [
    (stars: 2, factor: 0.55, name: 'Demo Lodge', area: 'near the station', bf: false, fc: true),
    (stars: 3, factor: 0.85, name: 'Sample Residency', area: 'city centre', bf: true, fc: true),
    (stars: 3, factor: 1.05, name: 'Demo Comfort Inn', area: 'main market', bf: true, fc: false),
    (stars: 4, factor: 1.65, name: 'Sample Grand', area: 'tourist area', bf: true, fc: true),
    (stars: 5, factor: 2.7, name: 'Demo Palace Resort', area: 'prime location', bf: true, fc: false),
  ];

  static int _seed(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  @override
  Future<HotelSearchResult> search({
    required City city,
    required DateTime checkIn,
    required DateTime checkOut,
    required int rooms,
    required int adults,
    required DateTime today,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final nights = checkOut.difference(checkIn).inDays;
    if (nights < 1) {
      return const HotelSearchResult(
          provider: 'Demo Hotel Rates', demo: true, currency: 'INR', offers: [], note: 'Check-out must be after check-in.');
    }
    final base = Estimator.hotelFor(city, HotelTier.standard);
    final rnd = Random(_seed('${city.name}|${checkIn.toIso8601String()}|$nights'));

    var weekend = 0;
    for (var i = 0; i < nights; i++) {
      final wd = checkIn.add(Duration(days: i)).weekday;
      if (wd == DateTime.friday || wd == DateTime.saturday) weekend++;
    }
    final weekendF = 1 + 0.10 * (weekend / nights);
    final lead = checkIn.difference(today).inDays;
    final leadF = lead <= 3 ? 1.12 : (lead > 45 ? 0.94 : 1.0);
    final m = checkIn.month;
    final seasonF = (m == 12 || m == 1 || m == 5 || m == 6 || m == 10) ? 1.15 : (m == 7 || m == 8 || m == 9 ? 0.90 : 1.0);

    final offers = <HotelOffer>[];
    for (final c in _classes) {
      final jitter = 0.94 + rnd.nextDouble() * 0.12;
      final price = ((base * c.factor * weekendF * leadF * seasonF * jitter) / 50).round() * 50.0;
      offers.add(HotelOffer(
        name: '${c.name} ${city.name}',
        stars: c.stars,
        area: c.area,
        pricePerNight: price,
        breakfast: c.bf,
        freeCancel: c.fc,
      ));
    }
    offers.sort((a, b) => a.pricePerNight.compareTo(b.pricePerNight));
    return HotelSearchResult(
      provider: 'Demo Hotel Rates',
      demo: true,
      currency: 'INR',
      offers: offers,
      note: '$nights night${nights == 1 ? '' : 's'}, $rooms room${rooms == 1 ? '' : 's'}',
    );
  }
}

class HotelService {
  static HotelRateProvider provider() => const DemoHotelApi();
}
