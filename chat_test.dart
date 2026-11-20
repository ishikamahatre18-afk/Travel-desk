import 'package:flutter_test/flutter_test.dart';
import 'package:travel_desk/ai/agent.dart';
import 'package:travel_desk/ai/tools.dart';
import 'package:travel_desk/chat/chat_models.dart';
import 'package:travel_desk/models.dart';
import 'package:travel_desk/services/flight_fares.dart';
import 'package:travel_desk/services/hotel_rates.dart';

/// A stand-in for the on-device model that plays back scripted replies.
class ScriptedLlm implements Llm {
  final List<String> replies;
  final List<String> seen = [];
  int _i = 0;
  ScriptedLlm(this.replies);
  @override
  Future<void> newChat() async {}
  @override
  Future<String> send(String text, {void Function(String soFar)? onText}) async {
    seen.add(text);
    final r = _i < replies.length ? replies[_i] : 'Done.';
    _i++;
    onText?.call(r);
    return r;
  }
}

void main() {
  final now = DateTime(2026, 11, 16, 10);

  ToolBox box() => ToolBox(
        store: DataStore.instance,
        fares: const DemoFlightApi(latency: Duration.zero),
        hotels: const DemoHotelApi(latency: Duration.zero),
        clock: () => now,
      );

  setUp(() => DataStore.instance.unload());

  group('tool call parser', () {
    test('reads a normal call', () {
      final c = ToolParser.parse('<tool>{"name":"list_rates","args":{}}</tool>');
      expect(c.single.name, 'list_rates');
    });
    test('survives a missing closing tag and extra words', () {
      final c = ToolParser.parse(
          'Sure! <tool>{"name":"save_price","args":{"kind":"hotel","amount":6500}}');
      expect(c.single.args['amount'], 6500);
    });
    test('accepts a bare json object and code fences', () {
      final c = ToolParser.parse('```json\n{"name":"list_rates","args":{}}\n```');
      expect(c.single.name, 'list_rates');
    });
    test('plain text has no calls and stays visible', () {
      expect(ToolParser.parse('Hello there'), isEmpty);
      expect(ToolParser.visible('Hi <tool>{"name":"x","args":{}}</tool>'), 'Hi');
    });
    test('braces inside strings do not confuse it', () {
      final c = ToolParser.parse('<tool>{"name":"remember","args":{"note":"a } b"}}</tool>');
      expect(c.single.args['note'], 'a } b');
    });
  });

  group('tools', () {
    test('make_quote builds cards and a client message', () async {
      final o = await box().run('make_quote', {
        'from': 'Indore', 'to': 'Goa', 'start': '2026-12-20', 'end': '2026-12-24', 'adults': 2,
      });
      expect(o.result, startsWith('QUOTE READY'));
      expect(o.show.any((m) => m.attachment is QuoteCard), isTrue);
      expect(o.show.any((m) => m.attachment is MessageCard), isTrue);
    });

    test('rejects past dates and missing fields with a clear error', () async {
      final past = await box().run('make_quote',
          {'from': 'Indore', 'to': 'Goa', 'start': '2026-10-01', 'end': '2026-10-04'});
      expect(past.result, contains('past'));
      final missing = await box().run('make_quote', {'to': 'Goa'});
      expect(missing.result, startsWith('ERROR'));
    });

    test('save_price stores owner prices that later quotes use', () async {
      final b = box();
      final s = await b.run('save_price',
          {'kind': 'flight', 'from': 'Indore', 'to': 'Goa', 'amount': 5200});
      expect(s.result, startsWith('SAVED'));
      expect(DataStore.instance.transports.single.source, 'owner');
      expect(DataStore.instance.transports.single.pricePerPerson, 5200);
    });

    test('one-off prices from a fare search are not saved', () async {
      final o = await box().run('make_quote', {
        'from': 'Indore', 'to': 'Delhi', 'start': '2026-12-18', 'end': '2026-12-20',
        'transport_price_per_person': 6100,
      });
      expect(o.result, contains('NOT saved'));
      expect(DataStore.instance.transports, isEmpty);
    });

    test('search_flights returns demo fares for the dates and cities', () async {
      final o = await box().run('search_flights',
          {'from': 'Indore', 'to': 'Delhi', 'date': '2026-12-18', 'adults': 2});
      final card = o.show.map((m) => m.attachment).whereType<FareCard>().first;
      expect(card.demo, isTrue);
      expect(card.rows, isNotEmpty);
      expect(o.result, contains('DEMO'));
    });

    test('search_hotels returns demo rates', () async {
      final o = await box().run('search_hotels',
          {'city': 'Goa', 'check_in': '2026-12-20', 'check_out': '2026-12-24'});
      final card = o.show.map((m) => m.attachment).whereType<HotelCard>().first;
      expect(card.demo, isTrue);
      expect(card.rows.length, greaterThan(2));
    });

    test('settings are validated', () async {
      final bad = await box().run('set_setting', {'name': 'markup', 'value': '500'});
      expect(bad.result, startsWith('ERROR'));
      final ok = await box().run('set_setting', {'name': 'markup', 'value': '12'});
      expect(ok.result, startsWith('SAVED'));
      expect(DataStore.instance.profile.markupPct, 12);
    });

    test('delete needs confirmation first', () async {
      final b = box();
      await b.run('save_price', {'kind': 'hotel', 'city': 'Goa', 'amount': 6500});
      final ask = await b.run('delete_rate', {'city': 'Goa'});
      expect(ask.result, startsWith('NEEDS CONFIRMATION'));
      expect(DataStore.instance.destinations, isNotEmpty);
      final done = await b.run('delete_rate', {'city': 'Goa', 'confirmed': true});
      expect(done.result, startsWith('DELETED'));
      expect(DataStore.instance.destinations, isEmpty);
    });

    test('remember stores a note once', () async {
      final b = box();
      await b.run('remember', {'note': 'Owner always quotes luxury hotels'});
      await b.run('remember', {'note': 'Owner always quotes luxury hotels'});
      expect(DataStore.instance.notes.length, 1);
    });
  });

  group('agent', () {
    Agent agent(ScriptedLlm llm) => Agent(
          llm: llm,
          tools: box(),
          store: DataStore.instance,
          accountName: 'test',
          clock: () => now,
        );

    test('runs a tool the model asks for, then shows its answer', () async {
      final llm = ScriptedLlm([
        'Ready.',
        '<tool>{"name":"make_quote","args":{"from":"Indore","to":"Goa","start":"2026-12-20","end":"2026-12-24","adults":2}}</tool>',
        'Here is your quote. Some prices are estimates.',
      ]);
      final out = await agent(llm).handle('quote indore to goa 20-24 dec');
      expect(out.any((m) => m.attachment is QuoteCard), isTrue);
      expect(out.last.text, contains('quote'));
      expect(llm.seen[2], contains('TOOL_RESULT make_quote'));
    });

    test('plain answers pass straight through', () async {
      final llm = ScriptedLlm(['Ready.', 'Goa is lovely in December.']);
      final out = await agent(llm).handle('is goa good in december?');
      expect(out.single.text, contains('Goa'));
    });

    test('the system prompt carries the owner\'s remembered notes', () async {
      DataStore.instance.notes.add('Owner prefers formal messages');
      final llm = ScriptedLlm(['Ready.', 'ok']);
      await agent(llm).handle('hi');
      expect(llm.seen.first, contains('Owner prefers formal messages'));
      expect(llm.seen.first, contains('2026-11-16'));
    });

    test('a model that loops on tools is stopped', () async {
      final llm = ScriptedLlm([
        'Ready.',
        for (var i = 0; i < 10; i++) '<tool>{"name":"list_rates","args":{}}</tool>',
      ]);
      final out = await agent(llm).handle('rates');
      expect(out.last.text, contains('stuck'));
    });
  });
}
