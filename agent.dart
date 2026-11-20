import 'dart:convert';

import 'package:intl/intl.dart';

import '../chat/chat_models.dart';
import '../models.dart';
import 'tools.dart';

/// Anything that can turn a message into a reply. The real one is the
/// on-device model; tests use a scripted one.
abstract class Llm {
  Future<String> send(String text, {void Function(String soFar)? onText});
  Future<void> newChat();
}

class ToolCall {
  final String name;
  final Map<String, dynamic> args;
  const ToolCall(this.name, this.args);
}

/// Reads `<tool>{...}</tool>` calls out of a model reply. Small models are
/// sloppy, so this accepts a missing closing tag, code fences and a bare JSON
/// object.
class ToolParser {
  static List<ToolCall> parse(String reply) {
    final calls = <ToolCall>[];
    var i = 0;
    while (true) {
      final s = reply.indexOf('<tool>', i);
      if (s < 0) break;
      final json = _object(reply, s + 6);
      if (json == null) break;
      final c = _toCall(json.$1);
      if (c != null) calls.add(c);
      i = json.$2;
    }
    if (calls.isEmpty) {
      final t = reply.trim().replaceAll(RegExp(r'^```(?:json)?|```$', multiLine: true), '').trim();
      if (t.startsWith('{') && t.contains('"name"')) {
        final j = _object(t, 0);
        final c = j == null ? null : _toCall(j.$1);
        if (c != null) calls.add(c);
      }
    }
    return calls;
  }

  static ToolCall? _toCall(String json) {
    try {
      final m = jsonDecode(json);
      if (m is! Map) return null;
      final name = m['name']?.toString();
      if (name == null || name.isEmpty) return null;
      final a = m['args'] ?? m['arguments'] ?? m['parameters'];
      return ToolCall(name, a is Map ? a.cast<String, dynamic>() : <String, dynamic>{});
    } catch (_) {
      return null;
    }
  }

  /// The first balanced `{...}` at or after [from], plus where it ended.
  static (String, int)? _object(String s, int from) {
    final start = s.indexOf('{', from);
    if (start < 0) return null;
    var depth = 0;
    var inStr = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return (s.substring(start, i + 1), i + 1);
      }
    }
    return null;
  }

  /// The reply without any tool call text.
  static String visible(String reply) {
    var t = reply.replaceAll(RegExp(r'<tool>.*?(</tool>|$)', dotAll: true), '');
    t = t.replaceAll(RegExp(r'```(?:json)?'), '');
    return t.trim();
  }
}

/// The assistant. The language model understands the owner and decides what
/// to do. Tools do the exact work. Prices on screen always come from the
/// tools, never from the model's own words.
class Agent {
  Agent({
    required this.llm,
    required this.tools,
    required this.store,
    required this.accountName,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Llm llm;
  final ToolBox tools;
  final DataStore store;
  final String accountName;
  final DateTime Function() _clock;

  static const maxSteps = 5;
  static const _rebuildAfterChars = 9000;

  bool _fresh = true;
  int _chars = 0;
  final List<String> _recent = [];

  static List<BotMessage> greeting() => const [
        BotMessage(
          'Hi! I\'m your Travel Desk assistant. Everything I do stays on this phone.\n\n'
          'Ask me anything about a trip. I can quote it, search flight and hotel rates, '
          'remember your prices and preferences, and write the message for your client.',
          replies: [
            QuickReply('Quote a trip', 'I want to quote a trip'),
            QuickReply('Search flights', 'Search flights for me'),
            QuickReply('Search hotels', 'Search hotels for me'),
            QuickReply('My saved prices', 'Show my saved prices'),
          ],
        ),
      ];

  String systemPrompt() {
    final now = _clock();
    final p = store.profile;
    final rates = <String>[];
    for (final t in store.transports.take(10)) {
      rates.add('${t.mode.label} ${t.from}->${store.destById(t.destinationId)?.name ?? '?'} ${t.pricePerPerson.round()}');
    }
    final notes = store.notes.isEmpty ? 'none yet' : store.notes.map((n) => '- $n').join('\n');
    return '''You are Travel Desk Assistant, the private offline assistant of a travel agency owner. You talk to the OWNER, not to the client. Agency: ${p.name}. Currency: ${p.currency}. Owner's account: $accountName.
Today is ${DateFormat('EEEE, yyyy-MM-dd').format(now)}.

RULES
1. Never invent prices, fares, hotel rates or totals. Every number comes from a tool. If you need a price, call a tool.
2. To use a tool, reply with ONLY the call, nothing else: <tool>{"name":"TOOL","args":{...}}</tool>
   You will then receive the result and must answer the owner in 1 to 3 short sentences. Cards (quote, fares, hotels, the client message) are shown to the owner automatically. Do not repeat their numbers or the client message.
3. If something needed is missing (departure city, destination, dates), ask ONE short question. Do not guess dates. Dates in tool args are YYYY-MM-DD. "Next Friday", "20-24 Dec" etc. must be converted using today's date; if the year is not given use the next future date.
4. Defaults when the owner does not say: 2 adults, 0 children, standard hotel, flight, return trip. Use what the notes below say instead.
5. When the owner states a preference or fact about their business or clients ("I always quote luxury hotels", "my Dubai clients prefer formal messages"), call remember. When the owner gives a real price, call save_price.
6. Fares and hotel rates from search tools are DEMO simulated data. Say so briefly. Never claim they are real or live.
7. Before delete_rate, ask the owner to confirm, and only then call it with confirmed true.
8. Be warm, calm and professional. Reply in the owner's language. For general travel questions (visas, seasons, itinerary ideas) answer from your own knowledge, and say when you are unsure.

TOOLS (args)
search_flights {from,to,date,adults,return_date?}
search_hotels {city,check_in,check_out,rooms?,adults?}
make_quote {from,to,start,end|nights,adults?,children?,rooms?,mode?(flight|road|ship),hotel_tier?(budget|standard|luxury),round_trip?,include_activities?,client?,tone?(friendly|formal),breakdown?,transport_price_per_person?,hotel_price_per_night?}
save_price {kind(flight|road|ship|hotel|meals|activities|local_transport),from?,to|city,tier?,amount}
list_rates {}
delete_rate {to|city,from?,confirmed?}
set_setting {name(markup|tax|child_discount|validity_days|currency|phone|agency_name),value}
remember {note}   forget_note {note}
share_message {via(copy|whatsapp)}
open_live_check {kind(flight|hotel),from?,to?,city?,start,end?,adults?}
account {action(change_password|new_recovery_code|lock|remove_account)}

EXAMPLES
Owner: quote Indore to Goa 20-24 Dec for 2 adults
You: <tool>{"name":"make_quote","args":{"from":"Indore","to":"Goa","start":"${now.year}-12-20","end":"${now.year}-12-24","adults":2}}</tool>
Owner: hotel in Goa is 6500 a night
You: <tool>{"name":"save_price","args":{"kind":"hotel","city":"Goa","tier":"standard","amount":6500}}</tool>

SAVED PRICES (owner's own): ${rates.isEmpty ? 'none yet' : rates.join('; ')}
Agency settings: markup ${p.markupPct}%, tax ${p.gstPct}%, child discount ${p.childDiscountPct}%, quotes valid ${p.validityDays} days.
WHAT THE OWNER HAS TOLD YOU TO REMEMBER:
$notes''';
  }

  Future<void> _startChat() async {
    await llm.newChat();
    _chars = 0;
    final intro = StringBuffer(systemPrompt());
    if (_recent.isNotEmpty) {
      intro.write('\n\nEARLIER IN THIS CONVERSATION (for context):\n${_recent.join('\n')}');
    }
    intro.write('\n\nReply "Ready." to confirm.');
    final ack = await llm.send(intro.toString());
    _chars = intro.length + ack.length;
    _fresh = false;
  }

  void _note(String who, String text) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return;
    _recent.add('$who: ${t.length > 220 ? '${t.substring(0, 220)}…' : t}');
    while (_recent.length > 8) {
      _recent.removeAt(0);
    }
  }

  /// Handles one message from the owner and returns what to show.
  Future<List<BotMessage>> handle(String text, {void Function(String soFar)? onText}) async {
    final out = <BotMessage>[];
    try {
      if (_fresh || _chars > _rebuildAfterChars) await _startChat();
      _note('Owner', text);

      var input = text;
      for (var step = 0; step < maxSteps; step++) {
        _chars += input.length;
        final reply = await llm.send(input, onText: (s) {
          if (onText != null && !s.contains('<tool') && !s.trimLeft().startsWith('{')) onText(s);
        });
        _chars += reply.length;

        final calls = ToolParser.parse(reply);
        if (calls.isEmpty) {
          final t = ToolParser.visible(reply);
          if (t.isEmpty) {
            out.add(const BotMessage('I couldn\'t put an answer together. Could you say that another way?'));
          } else {
            out.add(BotMessage(t));
            _note('Assistant', t);
          }
          return out;
        }

        final results = StringBuffer();
        for (final c in calls.take(3)) {
          final o = await tools.run(c.name, c.args);
          out.addAll(o.show);
          results.writeln('TOOL_RESULT ${c.name}: ${o.result}');
        }
        input = '${results.toString().trim()}\n'
            '(Now answer the owner in 1 to 3 short sentences, or call another tool if still needed.)';
      }
      out.add(const BotMessage('I got stuck on that. Please try again, maybe with fewer things at once.'));
      return out;
    } catch (e) {
      _fresh = true; // next message rebuilds the conversation
      out.add(BotMessage('Sorry, the assistant hit a problem ($e). Your data is safe. Please try again.'));
      return out;
    }
  }
}
