import 'package:flutter_test/flutter_test.dart';
import 'package:travel_desk/models.dart';
import 'package:travel_desk/services/auth_service.dart';
import 'package:travel_desk/services/message_composer.dart';
import 'package:travel_desk/services/planner.dart';

void main() {
  final dest = Destination(
    id: 'd1',
    name: 'Goa',
    hotelStandard: 1000,
    mealsPerDay: 100,
    peakMonths: [12],
    peakSurchargePct: 50,
    highlights: ['Beach', 'Fort'],
  );
  final rate = TransportRate(
      id: 't1', from: 'Delhi', destinationId: 'd1', mode: TravelMode.flight, pricePerPerson: 5000);
  final profile = AgencyProfile(markupPct: 10, gstPct: 0, childDiscountPct: 0);
  final today = DateTime(2026, 11, 16);

  Inquiry inquiry({DateTime? start, DateTime? end, int adults = 2, String origin = 'Delhi'}) => Inquiry(
        origin: origin,
        destinationId: 'd1',
        mode: TravelMode.flight,
        start: start ?? DateTime(2026, 11, 20),
        end: end ?? DateTime(2026, 11, 23),
        adults: adults,
        includeActivities: false,
      );

  test('computes a simple quote exactly', () {
    final r = Planner.build(q: inquiry(), profile: profile, dest: dest, rates: [rate], today: today);
    expect(r.ok, isTrue);
    // transport 5000*2*2=20000, hotel 1000*1 room*3 nights=3000, meals 100*4*2=800
    expect(r.subtotal, 23800);
    expect(r.markup, 2380);
    expect(r.total, 26180);
    expect(r.perPerson, 13090);
    final sum = r.clientLines.fold<double>(0, (s, l) => s + l.amount);
    expect(sum, r.total);
  });

  test('applies peak supplement for December nights', () {
    final r = Planner.build(
        q: inquiry(start: DateTime(2026, 12, 10), end: DateTime(2026, 12, 12)),
        profile: profile, dest: dest, rates: [rate], today: today);
    expect(r.ok, isTrue);
    expect(r.lines.any((l) => l.label.contains('Peak')), isTrue);
  });

  test('rejects past dates, same city and missing routes', () {
    expect(Planner.build(q: inquiry(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 5)),
        profile: profile, dest: dest, rates: [rate], today: today).ok, isFalse);
    expect(Planner.build(q: inquiry(origin: 'Goa'),
        profile: profile, dest: dest, rates: [rate], today: today).ok, isFalse);
    expect(Planner.build(q: inquiry(origin: 'Mumbai'),
        profile: profile, dest: dest, rates: [rate], today: today).ok, isFalse);
  });

  test('message contains plan and total', () {
    final q = inquiry();
    final r = Planner.build(q: q, profile: profile, dest: dest, rates: [rate], today: today);
    final text = MessageComposer.compose(
        q: q, profile: profile, dest: dest, r: r, tone: Tone.formal, showBreakdown: false, today: today);
    expect(text.contains('Day 1'), isTrue);
    expect(text.contains('Day 4'), isTrue);
    expect(text.contains('26,180'), isTrue);
  });

  test('password hashing is deterministic and compares safely', () {
    final a = pbkdf2Derive({'p': 'secret123', 's': [1, 2, 3], 'i': 10});
    final b = pbkdf2Derive({'p': 'secret123', 's': [1, 2, 3], 'i': 10});
    final c = pbkdf2Derive({'p': 'secret124', 's': [1, 2, 3], 'i': 10});
    expect(constantTimeEquals(a, b), isTrue);
    expect(constantTimeEquals(a, c), isFalse);
  });
}
