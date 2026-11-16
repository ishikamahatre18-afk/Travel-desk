import '../models.dart';

class QuoteLine {
  final String label;
  final String detail;
  final double amount;
  const QuoteLine(this.label, this.detail, this.amount);
}

class QuoteResult {
  final List<String> errors;
  final List<String> warnings;
  final List<QuoteLine> lines; // internal cost lines (before markup/tax)
  final List<QuoteLine> clientLines; // lines with markup + tax folded in
  final double subtotal;
  final double markup;
  final double tax;
  final double total;
  final double perPerson;
  final int nights;
  final int rooms;
  final TransportRate? rate;

  const QuoteResult({
    this.errors = const [],
    this.warnings = const [],
    this.lines = const [],
    this.clientLines = const [],
    this.subtotal = 0,
    this.markup = 0,
    this.tax = 0,
    this.total = 0,
    this.perPerson = 0,
    this.nights = 0,
    this.rooms = 0,
    this.rate,
  });

  bool get ok => errors.isEmpty;
}

/// Deterministic, fully offline planner. Every number comes from the owner's
/// own rate tables; nothing is guessed.
class Planner {
  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  static double _r(double v) => v.roundToDouble();

  static QuoteResult build({
    required Inquiry q,
    required AgencyProfile profile,
    required Destination dest,
    required List<TransportRate> rates,
    DateTime? today,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final now = _day(today ?? DateTime.now());
    final start = _day(q.start);
    final end = _day(q.end);
    final nights = end.difference(start).inDays;

    if (q.origin.trim().isEmpty) errors.add('Enter the departure city.');
    if (q.origin.trim().toLowerCase() == dest.name.trim().toLowerCase()) {
      errors.add('Departure city and destination are the same.');
    }
    if (start.isBefore(now)) errors.add('The start date is in the past.');
    if (nights < 1) errors.add('The trip must be at least 1 night.');
    if (nights > 60) errors.add('Trips longer than 60 nights need a manual quote.');
    if (start.difference(now).inDays > 730) {
      errors.add('The start date is more than 2 years away.');
    }
    if (q.adults < 1) errors.add('At least 1 adult is required.');
    if (q.adults + q.children > 50) {
      errors.add('Groups above 50 travellers need a manual quote.');
    }

    final autoRooms = (q.adults / 2).ceil().clamp(1, 1000);
    final rooms = q.rooms ?? autoRooms;
    if (rooms < 1) errors.add('At least 1 room is required.');
    if (rooms > 0 && rooms * 3 < q.adults + q.children) {
      warnings.add('$rooms room(s) for ${q.adults + q.children} travellers '
          'may be too crowded. Check occupancy.');
    }

    final hotelRate = dest.hotelRate(q.tier);
    if (hotelRate <= 0) {
      errors.add('No ${q.tier.label} hotel rate saved for ${dest.name}.');
    }

    TransportRate? rate;
    for (final r in rates) {
      if (r.mode == q.mode &&
          r.destinationId == dest.id &&
          r.from.trim().toLowerCase() == q.origin.trim().toLowerCase()) {
        rate = r;
        break;
      }
    }
    if (rate == null) {
      errors.add('No ${q.mode.label} rate saved from ${q.origin.trim()} '
          'to ${dest.name}. Add it under Rates.');
    } else if (rate.pricePerPerson <= 0) {
      errors.add('The saved ${q.mode.label} price is 0. Update it under Rates.');
    }

    if (errors.isNotEmpty) {
      return QuoteResult(errors: errors, warnings: warnings, nights: nights);
    }

    final disc = (profile.childDiscountPct / 100).clamp(0.0, 1.0);
    final payers = q.adults + q.children * (1 - disc);
    final days = nights + 1;

    var peakNights = 0;
    for (var i = 0; i < nights; i++) {
      final d = start.add(Duration(days: i));
      if (dest.peakMonths.contains(d.month)) peakNights++;
    }

    final lines = <QuoteLine>[];
    final legs = q.roundTrip ? 2 : 1;
    lines.add(QuoteLine(
      '${q.mode.label} ${q.roundTrip ? "(return)" : "(one way)"}',
      '${q.origin.trim()} → ${dest.name}',
      _r(rate!.pricePerPerson * payers * legs),
    ));
    lines.add(QuoteLine(
      'Hotel (${q.tier.label})',
      '$rooms room(s) × $nights night(s)',
      _r(hotelRate * rooms * nights),
    ));
    if (peakNights > 0 && dest.peakSurchargePct > 0) {
      lines.add(QuoteLine(
        'Peak-season supplement',
        '$peakNights night(s)',
        _r(hotelRate * rooms * peakNights * dest.peakSurchargePct / 100),
      ));
    }
    if (peakNights > 0) {
      warnings.add('$peakNights night(s) fall in peak season for ${dest.name}.');
    }
    if (dest.mealsPerDay > 0) {
      lines.add(QuoteLine('Meals', '$days day(s)', _r(dest.mealsPerDay * days * payers)));
    }
    if (q.includeActivities && dest.activitiesPerDay > 0) {
      lines.add(QuoteLine(
          'Sightseeing & activities', '$days day(s)', _r(dest.activitiesPerDay * days * payers)));
    }
    if (dest.localTransportPerDay > 0) {
      lines.add(QuoteLine('Local transport', '$days day(s)',
          _r(dest.localTransportPerDay * days * payers)));
    }

    if (dest.name.toUpperCase().contains('SAMPLE')) {
      warnings.add('This destination is SAMPLE data. Replace it with your real rates.');
    }
    if (rate.mode == TravelMode.road && rate.hours > 14) {
      warnings.add('Road journey is over 14 hours each way. Confirm with the client.');
    }

    final subtotal = lines.fold<double>(0, (s, l) => s + l.amount);
    final markup = _r(subtotal * profile.markupPct / 100);
    final tax = _r((subtotal + markup) * profile.gstPct / 100);
    final total = _r(subtotal + markup + tax);
    final heads = q.adults + q.children;

    // Fold markup + tax into each line so a client-facing breakdown adds up.
    final factor = subtotal == 0 ? 1.0 : total / subtotal;
    final scaled = <double>[for (final l in lines) _r(l.amount * factor)];
    final diff = total - scaled.fold<double>(0, (s, v) => s + v);
    scaled[scaled.length - 1] += diff;
    final clientLines = <QuoteLine>[
      for (var i = 0; i < lines.length; i++)
        QuoteLine(lines[i].label, lines[i].detail, scaled[i]),
    ];

    return QuoteResult(
      warnings: warnings,
      lines: lines,
      clientLines: clientLines,
      subtotal: subtotal,
      markup: markup,
      tax: tax,
      total: total,
      perPerson: _r(total / heads),
      nights: nights,
      rooms: rooms,
      rate: rate,
    );
  }
}
