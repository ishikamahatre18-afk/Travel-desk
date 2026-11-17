import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models.dart';

/// Optional online extras. Every call is read-only, uses HTTPS, sends no
/// credentials or client details, and fails quietly to null when offline.
class LiveApi {
  static const _timeout = Duration(seconds: 8);
  static const supportedFx = ['USD', 'EUR', 'GBP', 'AUD', 'CAD', 'SGD', 'CHF', 'JPY'];

  static Future<String?> weather(String place, DateTime start, DateTime end) async {
    try {
      final today = DateTime.now();
      final t0 = DateTime(today.year, today.month, today.day);
      final s = DateTime(start.year, start.month, start.day);
      if (s.difference(t0).inDays > 14) return null; // forecast window is ~16 days
      var e = DateTime(end.year, end.month, end.day);
      final cap = t0.add(const Duration(days: 15));
      if (e.isAfter(cap)) e = cap;

      final clean = place.replaceAll(RegExp(r'\(.*?\)'), '').trim();
      final geo = await http
          .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
              {'name': clean, 'count': '1', 'language': 'en'}))
          .timeout(_timeout);
      if (geo.statusCode != 200) return null;
      final results = (jsonDecode(geo.body) as Map)['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final lat = (results[0]['latitude'] as num).toString();
      final lon = (results[0]['longitude'] as num).toString();

      final f = DateFormat('yyyy-MM-dd');
      final res = await http
          .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': lat,
            'longitude': lon,
            'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
            'start_date': f.format(s),
            'end_date': f.format(e),
            'timezone': 'auto',
          }))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final daily = (jsonDecode(res.body) as Map)['daily'] as Map?;
      if (daily == null) return null;
      List<num> nums(String k) => ((daily[k] as List?) ?? [])
          .whereType<num>()
          .toList();
      final hi = nums('temperature_2m_max');
      final lo = nums('temperature_2m_min');
      final rain = nums('precipitation_probability_max');
      if (hi.isEmpty || lo.isEmpty) return null;
      final maxT = hi.reduce((a, b) => a > b ? a : b).round();
      final minT = lo.reduce((a, b) => a < b ? a : b).round();
      final rainMax = rain.isEmpty ? null : rain.reduce((a, b) => a > b ? a : b).round();
      final rainTxt = rainMax == null ? '' : ', rain chance up to $rainMax%';
      return 'Forecast: $minT°C to $maxT°C$rainTxt (live forecast, may change).';
    } catch (_) {
      return null;
    }
  }

  /// Returns an indicative converted total line, or null.
  static Future<String?> fxLine(String base, String target, double amount) async {
    try {
      if (base.toUpperCase() == target.toUpperCase()) return null;
      final res = await http
          .get(Uri.https('api.frankfurter.dev', '/v1/latest',
              {'base': base.toUpperCase(), 'symbols': target.toUpperCase()}))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map;
      final rate = ((j['rates'] as Map?)?[target.toUpperCase()]) as num?;
      if (rate == null) return null;
      final converted = NumberFormat.decimalPattern().format((amount * rate).round());
      return 'Approx. $target $converted (indicative rate, ${j['date']}).';
    } catch (_) {
      return null;
    }
  }
}

/// Builds search links that open in the phone's browser. Only city names,
/// dates and traveller counts are placed in a link. Never client names,
/// agency details, rates or login data.
class LiveLinks {
  static String _clean(String s) => s.replaceAll(RegExp(r'\(.*?\)'), '').trim();
  static String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static Uri transport({
    required TravelMode mode,
    required String from,
    required String to,
    required DateTime start,
    required DateTime end,
    required bool roundTrip,
  }) {
    final f = _clean(from);
    final t = _clean(to);
    switch (mode) {
      case TravelMode.flight:
        final q = roundTrip
            ? 'Flights from $f to $t on ${_d(start)} returning ${_d(end)}'
            : 'Flights from $f to $t on ${_d(start)}';
        return Uri.https('www.google.com', '/travel/flights', {'q': q});
      case TravelMode.road:
        return Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'origin': f,
          'destination': t,
          'travelmode': 'driving',
        });
      case TravelMode.ship:
        return Uri.https('www.google.com', '/search',
            {'q': 'ship or ferry from $f to $t ticket price'});
    }
  }

  static Uri hotel({
    required String place,
    required DateTime start,
    required DateTime end,
    required int adults,
    required int children,
    required int rooms,
  }) {
    return Uri.https('www.booking.com', '/searchresults.html', {
      'ss': _clean(place),
      'checkin': _d(start),
      'checkout': _d(end),
      'group_adults': '$adults',
      'group_children': '$children',
      'no_rooms': '$rooms',
    });
  }
}
