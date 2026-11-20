import 'package:intl/intl.dart';

import '../models.dart';
import 'planner.dart';

enum Tone { friendly, formal }

class MessageComposer {
  static String money(AgencyProfile p, double v) {
    final n = NumberFormat.decimalPattern('en_IN').format(v.round());
    final sym = p.currency.toUpperCase() == 'INR' ? '₹' : '${p.currency} ';
    return '$sym$n';
  }

  static String _date(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

  static String _plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  static String compose({
    required Inquiry q,
    required AgencyProfile profile,
    required Destination dest,
    required QuoteResult r,
    required Tone tone,
    required bool showBreakdown,
    String? weather,
    String? fxLine,
    bool estimated = false,
    DateTime? today,
  }) {
    if (!r.ok) return '';
    final friendly = tone == Tone.friendly;
    String e(String emoji) => friendly ? '$emoji ' : '';
    final b = StringBuffer();
    final name = q.clientName.trim();
    final dest0 = dest.country.isEmpty ? dest.name : '${dest.name}, ${dest.country}';
    final days = r.nights + 1;

    if (friendly) {
      b.writeln(name.isEmpty ? 'Hello! 😊' : 'Hello $name! 😊');
      b.writeln();
      b.writeln('Thank you for your interest in travelling with ${profile.name}. '
          'Here is a suggested plan for $dest0:');
    } else {
      b.writeln(name.isEmpty ? 'Dear Sir/Madam,' : 'Dear $name,');
      b.writeln();
      b.writeln('Thank you for contacting ${profile.name}. '
          'Please find the proposed itinerary and quotation for $dest0 below.');
    }
    b.writeln();

    // Trip summary
    b.writeln('${e('📍')}TRIP SUMMARY');
    b.writeln('From: ${q.origin.trim()}');
    b.writeln('To: ${dest.name}');
    final hrs = r.rate != null && r.rate!.hours > 0
        ? ' (approx. ${_trimNum(r.rate!.hours)} hrs each way)'
        : '';
    b.writeln('Travel: ${q.mode.label}${q.roundTrip ? ", return" : ", one way"}$hrs');
    b.writeln('Dates: ${_date(q.start)} to ${_date(q.end)}');
    b.writeln('Duration: ${_plural(r.nights, "night")} / ${_plural(days, "day")}');
    final pax = StringBuffer(_plural(q.adults, 'adult'));
    if (q.children > 0) pax.write(', ${_plural(q.children, "child", "children")}');
    b.writeln('Travellers: $pax');
    b.writeln('Stay: ${q.tier.label} hotel, ${_plural(r.rooms, "room")}');
    b.writeln();

    // Day-by-day
    b.writeln('${e('🗓️')}DAY-BY-DAY PLAN');
    final middle = days - 2;
    final buckets = List.generate(middle < 0 ? 0 : middle, (_) => <String>[]);
    if (buckets.isNotEmpty) {
      for (var i = 0; i < dest.highlights.length; i++) {
        buckets[i % buckets.length].add(dest.highlights[i]);
      }
    }
    final startD = DateTime(q.start.year, q.start.month, q.start.day);
    for (var i = 0; i < days; i++) {
      final d = DateFormat('d MMM').format(startD.add(Duration(days: i)));
      String text;
      if (i == 0) {
        text = 'Depart ${q.origin.trim()} by ${q.mode.label.toLowerCase()}, '
            'arrive in ${dest.name} and check in to your hotel.';
      } else if (i == days - 1) {
        text = q.roundTrip
            ? 'Check out and return to ${q.origin.trim()}.'
            : 'Check out. Onward travel as discussed.';
      } else {
        final items = buckets[i - 1];
        text = items.isEmpty
            ? 'Leisure day / local sightseeing at your own pace.'
            : items.join(', ');
      }
      b.writeln('Day ${i + 1} ($d): $text');
    }
    b.writeln();

    // Inclusions
    b.writeln('${e('✅')}PACKAGE INCLUDES');
    for (final l in r.clientLines) {
      b.writeln('- ${l.label}');
    }
    b.writeln();

    // Price
    b.writeln('${e('💰')}PRICE');
    if (showBreakdown) {
      for (final l in r.clientLines) {
        b.writeln('${l.label}: ${money(profile, l.amount)}');
      }
      b.writeln('---');
    }
    b.writeln('Total package: ${money(profile, r.total)}');
    b.writeln('Approx. per person: ${money(profile, r.perPerson)}');
    if (profile.gstPct > 0) b.writeln('(Inclusive of applicable taxes)');
    if (estimated) {
      b.writeln('(Indicative estimate. Final price is confirmed at booking.)');
    }
    if (fxLine != null) b.writeln(fxLine);
    b.writeln();

    if (weather != null) {
      b.writeln('${e('🌤️')}$weather');
      b.writeln();
    }
    if (dest.visaNote.trim().isNotEmpty) {
      b.writeln('${e('📄')}DOCUMENTS / VISA');
      b.writeln(dest.visaNote.trim());
      b.writeln();
    }

    b.writeln('${e('ℹ️')}NOT INCLUDED');
    b.writeln('Anything not listed above, personal expenses, and optional extras.');
    b.writeln();

    final t = today ?? DateTime.now();
    final valid = DateTime(t.year, t.month, t.day)
        .add(Duration(days: profile.validityDays));
    b.writeln('Prices are valid until ${_date(valid)} and subject to availability.');
    b.writeln();
    if (friendly) {
      b.writeln('Happy to adjust anything to suit you. Just let me know! ✨');
    } else {
      b.writeln('Please let us know if you would like any changes.');
    }
    b.writeln();
    b.writeln(profile.phone.trim().isEmpty
        ? profile.name
        : '${profile.name}\n${profile.phone.trim()}');
    return b.toString().trimRight();
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
