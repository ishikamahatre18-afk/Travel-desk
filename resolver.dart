import '../data/cities.dart';
import '../models.dart';
import 'estimator.dart';

/// Joins the owner's saved prices with built-in estimates. Saved prices
/// always win. Estimates only fill gaps, and are flagged as estimates.
class Resolver {
  static bool _estimatesOn(DataStore s) =>
      s.profile.currency.trim().toUpperCase() == 'INR';

  static Destination? destination(
      String idOrEstimate, Inquiry q, DataStore store) {
    Destination? base;
    if (idOrEstimate.startsWith('est:')) {
      final c = findCity(idOrEstimate.substring(4));
      if (c == null || !_estimatesOn(store)) return null;
      return Estimator.destination(c);
    }
    base = store.destById(idOrEstimate);
    if (base == null) return null;

    // Saved destination with no price for the chosen hotel level: fill the
    // gap with an estimate (on a copy, never on the saved record).
    if (base.hotelRate(q.tier) <= 0 && _estimatesOn(store)) {
      final c = findCity(base.name);
      if (c != null) {
        final copy = Destination.fromJson(base.toJson());
        final est = Estimator.hotelFor(c, q.tier);
        switch (q.tier) {
          case HotelTier.budget:
            copy.hotelBudget = est;
          case HotelTier.standard:
            copy.hotelStandard = est;
          case HotelTier.luxury:
            copy.hotelLuxury = est;
        }
        copy.source = 'estimate';
        return copy;
      }
    }
    return base;
  }

  static bool _matches(TransportRate t, Inquiry q, Destination dest) =>
      t.mode == q.mode &&
      t.destinationId == dest.id &&
      t.from.trim().toLowerCase() == q.origin.trim().toLowerCase();

  /// Saved routes plus, when none is saved for this trip, one estimate.
  static List<TransportRate> ratesFor(
      Inquiry q, Destination dest, DataStore store) {
    final list = [...store.transports];
    if (list.any((t) => _matches(t, q, dest)) || !_estimatesOn(store)) {
      return list;
    }
    final from = findCity(q.origin);
    final to = findCity(dest.name);
    if (from == null || to == null) return list;
    final est = Estimator.transport(
      from: from,
      to: to,
      mode: q.mode,
      fromLabel: q.origin.trim(),
      destId: dest.id,
    );
    if (est != null) list.add(est);
    return list;
  }
}
