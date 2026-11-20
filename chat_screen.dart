import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/agent.dart';
import '../ai/brain.dart';
import '../ai/tools.dart';
import '../chat/account_actions.dart';
import '../chat/chat_models.dart';
import '../services/account_service.dart';
import '../models.dart';
import '../services/cloud_service.dart';
import '../theme.dart';

class _Item {
  final bool mine;
  final String text;
  final BotMessage? bot;
  _Item.user(this.text)
      : mine = true,
        bot = null;
  _Item.bot(BotMessage m)
      : mine = false,
        text = m.text,
        bot = m;
}

/// The whole app after login: one chat with the offline assistant.
class ChatScreen extends StatefulWidget {
  final Session session;
  final VoidCallback onLock;
  final ValueChanged<Session> onSessionChanged;
  const ChatScreen({
    super.key,
    required this.session,
    required this.onLock,
    required this.onSessionChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final Agent _agent;
  String _partial = '';
  final _items = <_Item>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _agent = Agent(
      llm: Brain.instance,
      tools: ToolBox(store: DataStore.instance),
      store: DataStore.instance,
      accountName: widget.session.account.name,
    );
    for (final m in Agent.greeting()) {
      _items.add(_Item.bot(m));
    }
    Brain.instance.check();
  }

  @override
  void dispose() {
    Brain.instance.resetChat(); // the conversation never survives a lock
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _items.add(_Item.user(t));
      _busy = true;
    });
    _toEnd();
    List<BotMessage> replies;
    try {
      replies = await _agent.handle(t, onText: (s) {
        if (mounted) setState(() => _partial = s);
        _toEnd();
      });
    } catch (e) {
      replies = [BotMessage('Something went wrong ($e). Your data is safe.')];
    }
    if (!mounted) return;
    setState(() {
      for (final m in replies) {
        _items.add(_Item.bot(m));
      }
      _partial = '';
      _busy = false;
    });
    _toEnd();
    for (final m in replies) {
      if (m.action != null) await _run(m.action!);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    setState(() => _items.add(_Item.bot(BotMessage(text))));
    _toEnd();
  }

  Future<void> _run(ChatAction a) async {
    switch (a.type) {
      case ChatActionType.pickDates:
        await _pickDates();
      case ChatActionType.copy:
        await Clipboard.setData(ClipboardData(text: a.text ?? ''));
      case ChatActionType.whatsapp:
        final uri = Uri.https('wa.me', '/', {'text': a.text ?? ''});
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) _say('I couldn\'t open WhatsApp. Use Copy and paste the message instead.');
      case ChatActionType.openLink:
        final ok = a.uri != null &&
            await launchUrl(a.uri!, mode: LaunchMode.externalApplication);
        if (!ok) _say('I couldn\'t open the browser.');
      case ChatActionType.lock:
        widget.onLock();
      case ChatActionType.changePassword:
        final s = await AccountActions.changePassword(context, widget.session);
        if (s != null) widget.onSessionChanged(s);
        _say(s != null ? (AccountActions.lastNote ?? 'Password changed.') : 'Password not changed.');
      case ChatActionType.newRecovery:
        final s = await AccountActions.newRecoveryCode(context, widget.session);
        if (s != null) widget.onSessionChanged(s);
        _say(AccountActions.lastNote ?? 'Done.');
      case ChatActionType.removeAccount:
        final ok = await AccountActions.confirmRemove(context, widget.session);
        if (!ok) {
          _say('Okay, the account stays on this phone.');
          return;
        }
        final id = widget.session.account.id;
        widget.onLock();
        await AccountService.remove(id);
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final r = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 360)),
      helpText: 'Travel dates',
    );
    if (r == null) return;
    final f = DateFormat('d MMM');
    await _send(r.start == r.end ? f.format(r.start) : '${f.format(r.start)} - ${f.format(r.end)}');
  }

  Future<void> _tapReply(QuickReply q) async {
    if (q.action != null) {
      await _run(q.action!);
    } else {
      await _send(q.send);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Quick replies only under the newest bot message.
    int lastWithReplies = -1;
    if (_items.isNotEmpty && !_items.last.mine) {
      lastWithReplies = _items.length - 1;
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AppTheme.teal.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.travel_explore, size: 20, color: AppTheme.teal),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Travel Desk', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ValueListenableBuilder<SyncState>(
                valueListenable: CloudService.instance.state,
                builder: (c, st, _) => Text(
                  'Private · works offline${CloudService.configured ? ' · ${st.text}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w400),
                ),
              ),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: widget.onLock,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              itemCount: _items.length + (_busy ? 1 : 0),
              itemBuilder: (c, i) {
                if (i >= _items.length) {
                  return _partial.isEmpty
                      ? const _Typing()
                      : _Bubble(
                          item: _Item.bot(BotMessage(_partial)),
                          showReplies: false,
                          onReply: (_) {},
                          onSend: (_) {},
                          onCopy: (_) {},
                          onWhatsApp: (_) {},
                        );
                }
                final it = _items[i];
                return _Bubble(
                  item: it,
                  showReplies: i == lastWithReplies && !_busy,
                  onReply: _tapReply,
                  onSend: _send,
                  onCopy: (t) async {
                    await Clipboard.setData(ClipboardData(text: t));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied. Ready to paste.')));
                    }
                  },
                  onWhatsApp: (t) => _run(ChatAction(ChatActionType.whatsapp, text: t)),
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: Brain.instance,
            builder: (c, _) => Brain.instance.state == BrainState.ready
                ? _InputBar(
                    controller: _input,
                    focus: _focus,
                    busy: _busy,
                    onSend: () => _send(_input.text),
                  )
                : const _SetupPanel(),
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Item item;
  final bool showReplies;
  final ValueChanged<QuickReply> onReply;
  final ValueChanged<String> onSend;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onWhatsApp;
  const _Bubble({
    required this.item,
    required this.showReplies,
    required this.onReply,
    required this.onSend,
    required this.onCopy,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (item.mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 8, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AppTheme.teal,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(5),
            ),
          ),
          child: Text(item.text, style: const TextStyle(color: Colors.white, fontSize: 15.5, height: 1.35)),
        ),
      );
    }
    final m = item.bot!;
    final att = m.attachment;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w * 0.92),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.text.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8, right: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border.fromBorderSide(BorderSide(color: AppTheme.line)),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: SelectableText(m.text,
                  style: const TextStyle(color: AppTheme.ink, fontSize: 15.5, height: 1.4)),
            ),
          if (att is QuoteCard) _quoteCard(att),
          if (att is MessageCard) _messageCard(att),
          if (att is FareCard) _fareCard(att),
          if (att is HotelCard) _hotelCard(att),
          if (showReplies && m.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in m.replies)
                  ActionChip(
                    label: Text(q.label),
                    onPressed: () => onReply(q),
                    backgroundColor: AppTheme.teal.withValues(alpha: 0.08),
                    side: BorderSide(color: AppTheme.teal.withValues(alpha: 0.35)),
                    labelStyle: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _quoteCard(QuoteCard c) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.route, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 4),
          Text(c.dates, style: const TextStyle(color: Colors.black54)),
          Text(c.travellers, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(c.total, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.teal)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('${c.perPerson} per person', style: const TextStyle(color: Colors.black54)),
            ),
          ]),
          if (c.estimated)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.sun.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Estimate (about ±35%). Correct me and I\'ll remember.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.ink)),
            ),
          for (final n in c.notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $n', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ),
        ]),
      );

  Widget _messageCard(MessageCard c) => Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF8F6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.teal.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: SelectableText(c.text,
                style: const TextStyle(color: AppTheme.ink, fontSize: 14.5, height: 1.45)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(children: [
              TextButton.icon(
                  onPressed: () => onCopy(c.text),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy')),
              TextButton.icon(
                  onPressed: () => onWhatsApp(c.text),
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('WhatsApp')),
            ]),
          ),
        ]),
      );

  Widget _hotelCard(HotelCard c) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(c.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            ),
            if (c.demo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.sun.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('DEMO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 2),
          Text(c.subtitle, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final r in c.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                    Text(r.meta, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(r.price,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: r.cheapest ? AppTheme.teal : AppTheme.ink)),
                  if (r.cheapest)
                    const Text('Lowest', style: TextStyle(fontSize: 11, color: AppTheme.teal)),
                ]),
              ]),
            ),
          const Divider(height: 14),
          Text(c.footnote, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ]),
      );

  Widget _fareCard(FareCard c) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(c.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            ),
            if (c.demo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.sun.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('DEMO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 2),
          Text(c.subtitle, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final r in c.rows)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSend('use fare ${r.index}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.airline, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                      Text('${r.times}  ·  ${r.meta}',
                          style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(r.price,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: r.cheapest ? AppTheme.teal : AppTheme.ink)),
                    if (r.cheapest)
                      const Text('Cheapest', style: TextStyle(fontSize: 11, color: AppTheme.teal)),
                  ]),
                ]),
              ),
            ),
          const Divider(height: 14),
          Text(c.footnote, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ]),
      );
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel();
  @override
  Widget build(BuildContext context) {
    final b = Brain.instance;
    Widget body;
    switch (b.state) {
      case BrainState.checking:
      case BrainState.loading:
        body = const Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.teal)),
          SizedBox(width: 12),
          Expanded(child: Text('Waking up your assistant…')),
        ]);
      case BrainState.downloading:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Installing your assistant… ${b.progress}%',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: b.progress <= 0 ? null : b.progress / 100, minHeight: 6, color: AppTheme.teal),
          const SizedBox(height: 6),
          const Text('Keep the app open and stay on Wi-Fi. This happens only once.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54)),
        ]);
      case BrainState.notInstalled:
      case BrainState.error:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              b.state == BrainState.error
                  ? (b.error ?? 'Something went wrong.')
                  : 'One-time setup: install your private assistant',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
          const SizedBox(height: 4),
          const Text(
              'It downloads once (a few GB, use Wi-Fi). After that it works fully offline, and your chats never leave this phone.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => b.install(),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
            child: Text(b.state == BrainState.error ? 'Try again' : 'Install assistant'),
          ),
        ]);
      case BrainState.ready:
        body = const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: body,
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.line),
          ),
          child: const SizedBox(
              width: 34, child: LinearProgressIndicator(minHeight: 3, color: AppTheme.teal)),
        ),
      );
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          border: Border(top: BorderSide(color: AppTheme.line)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Message your assistant…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: const BorderSide(color: AppTheme.line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: const BorderSide(color: AppTheme.line)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: const BorderSide(color: AppTheme.teal, width: 1.6)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: busy ? null : onSend,
            style: IconButton.styleFrom(
                backgroundColor: AppTheme.teal, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.arrow_upward),
          ),
        ]),
      );
}
