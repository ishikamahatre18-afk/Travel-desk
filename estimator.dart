import 'dart:math';

import '../data/cities.dart';
import '../models.dart';

/// Offline price estimator. It works from distance and a cost tier, so it
/// can price any pair of built-in cities without any saved data. Results are
/// ballpark figures (INR) and are always labelled as estimates. Once the
/// owner confirms or corrects a price, his own number replaces the estimate.
class Estimator {
  static const _hotelStd = {1: 2400.0, 2: 3400.0, 3: 5000.0, 4: 7500.0, 5: 12000.0};
  static const _meals = {1: 500.0, 2: 650.0, 3: 900.0, 4: 1500.0, 5: 3000.0};
  static const _acts = {1: 350.0, 2: 500.0, 3: 800.0, 4: 1500.0, 5: 2500.0};
  static const _local = {1: 250.0, 2: 300.0, 3: 450.0, 4: 700.0, 5: 1200.0};

  static double _round(double v, double step) => (v / step).round() * step;

  static double km(City a, City b) {
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLon = rad(b.lon - a.lon);
    final s1 = sin(dLat / 2);
    final s2 = sin(dLon / 2);
    final h = s1 * s1 + cos(rad(a.lat)) * cos(rad(b.lat)) * s2 * s2;
    return 2 * r * asin(sqrt(h));
  }

  /// One-way price per person, or null when no sensible estimate exists.
  static TransportRate? transport({
    required City from,
    required City to,
    required TravelMode mode,
    required String fromLabel,
    required String destId,
  }) {
    final d = km(from, to);
    final domestic = from.country == to.country;
    double price;
    double hours;
    switch (mode) {
      case TravelMode.flight:
        if (d < 150) return null;
        if (domestic) {
          price = 1800 + 3.6 * min(d, 1200) + 2.2 * max(0, d - 1200);
          hours = 0.8 + d / 700;
        } else {
          price = 5000 + 3.0 * min(d, 4500) + 6.0 * max(0, d - 4500);
          hours = 1.0 + d / 780;
        }
      case TravelMode.road:
        if (!domestic) return null;
        final road = d * 1.3;
        if (road > 2500 || d < 5) return null;
        price = 100 + 1.8 * road;
        hours = road / 50;
      case TravelMode.ship:
        return null;
    }
    return TransportRate(
      id: 'est',
      from: fromLabel,
      destinationId: destId,
      mode: mode,
      pricePerPerson: _round(price, 50),
      hours: _round(hours, 0.5),
      source: 'estimate',
    );
  }

  static Destination destination(City c) {
    final t = c.tier.clamp(1, 5);
    final std = _hotelStd[t]!;
    return Destination(
      id: 'est:${c.name}',
      name: c.name,
      country: c.country,
      hotelBudget: _round(std * 0.55, 50),
      hotelStandard: std,
      hotelLuxury: _round(std * 2.2, 50),
      mealsPerDay: _meals[t]!,
      activitiesPerDay: _acts[t]!,
      localTransportPerDay: _local[t]!,
      source: 'estimate',
    );
  }

  /// Hotel price for one tier, used to fill a gap in a saved destination.
  static double hotelFor(City c, HotelTier tier) =>
      destination(c).hotelRate(tier);
}
