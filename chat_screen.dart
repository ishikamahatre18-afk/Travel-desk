import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/agent.dart';
import '../ai/brain.dart';
import '../ai/tools.dart';
import '../ai/voice.dart';
import '../chat/account_actions.dart';
import '../chat/chat_models.dart';
import '../services/account_service.dart';
import '../models.dart';
import '../services/cloud_service.dart';
import '../theme.dart';
import '../widgets.dart';

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
  var _seen = 0; // bubbles that have already played their entrance

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
    Voice.instance.init();
  }

  @override
  void dispose() {
    Brain.instance.resetChat(); // the conversation never survives a lock
    Voice.instance.stop();
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
    HapticFeedback.selectionClick();
    Voice.instance.stop();
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
    final spoken = replies
        .where((m) => m.attachment == null && m.action == null && m.text.isNotEmpty)
        .map((m) => m.text)
        .join(' ');
    if (spoken.isNotEmpty) Voice.instance.speak(spoken);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _seen = _items.length);
    // Quick replies only under the newest bot message.
    int lastWithReplies = -1;
    if (_items.isNotEmpty && !_items.last.mine) {
      lastWithReplies = _items.length - 1;
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        shape: const Border(bottom: BorderSide(color: AppTheme.line, width: 0.8)),
        title: Row(children: [
          const AppLogo(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Travel Desk',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              ListenableBuilder(
                listenable: Voice.instance,
                builder: (c, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Voice.instance.speaking
                      ? const Row(key: ValueKey('speaking'), children: [
                          SpeakingBars(),
                          SizedBox(width: 6),
                          Text('Speaking', style: TextStyle(fontSize: 11.5, color: AppTheme.teal)),
                        ])
                      : ValueListenableBuilder<SyncState>(
                          key: const ValueKey('status'),
                          valueListenable: CloudService.instance.state,
                          builder: (c, st, _) => Text(
                            'Private · works offline${CloudService.configured ? ' · ${st.text}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w400),
                          ),
                        ),
                ),
              ),
            ]),
          ),
        ]),
        actions: [
          ListenableBuilder(
            listenable: Voice.instance,
            builder: (c, _) => IconButton(
              tooltip: Voice.instance.enabled ? 'Mute voice' : 'Turn voice on',
              onPressed: () => Voice.instance.setEnabled(!Voice.instance.enabled),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                child: Icon(
                  Voice.instance.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  key: ValueKey(Voice.instance.enabled),
                  color: Voice.instance.enabled ? AppTheme.teal : Colors.black45,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: widget.onLock,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FCFC), Color(0xFFEDF5F5)],
          ),
        ),
        child: SafeArea(
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
                final fresh = i >= _seen;
                return Appear(
                  animate: fresh,
                  from: it.mine ? const Offset(14, 6) : const Offset(-10, 10),
                  child: _Bubble(
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
                  ),
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
                for (var qi = 0; qi < m.replies.length; qi++)
                  Appear(
                    delay: Duration(milliseconds: 120 + 70 * qi),
                    from: const Offset(0, 8),
                    child: _chip(m.replies[qi]),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _chip(QuickReply q) => ActionChip(
        label: Text(q.label),
        onPressed: () => onReply(q),
        backgroundColor: Colors.white,
        elevation: 0,
        pressElevation: 0,
        side: BorderSide(color: AppTheme.teal.withValues(alpha: 0.30)),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600, fontSize: 13.5),
      );

  Widget _quoteCard(QuoteCard c) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.line),
          boxShadow: AppTheme.softShadow,
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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.line),
          boxShadow: AppTheme.softShadow,
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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.line),
          boxShadow: AppTheme.softShadow,
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
          child: const ThinkingDots(),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.line),
            boxShadow: AppTheme.softShadow,
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 15.5, color: AppTheme.ink),
                decoration: const InputDecoration(
                  hintText: 'Ask anything about a trip…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (c, v, _) {
                final can = v.text.trim().isNotEmpty && !busy;
                return AnimatedScale(
                  scale: can ? 1 : 0.86,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: can ? 1 : 0.45,
                    duration: const Duration(milliseconds: 180),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: IconButton.filled(
                        onPressed: can ? onSend : null,
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.teal,
                          disabledBackgroundColor: AppTheme.teal,
                          minimumSize: const Size(44, 44),
                        ),
                        icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      );
}
