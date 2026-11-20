import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData? icon;
  const SectionCard({super.key, required this.title, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppTheme.teal),
                const SizedBox(width: 8),
              ],
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink)),
            ]),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class CountStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const CountStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 50,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
      IconButton.outlined(
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: 40,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      IconButton.outlined(
        onPressed: value < max ? () => onChanged(value + 1) : null,
        icon: const Icon(Icons.add),
      ),
    ]);
  }
}

class NoticeCard extends StatelessWidget {
  final String text;
  final bool error;
  const NoticeCard({super.key, required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFD64545) : const Color(0xFFE69A3A);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.error_outline : Icons.warning_amber_rounded,
            color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: AppTheme.ink))),
      ]),
    );
  }
}

Widget gap([double h = 14]) => SizedBox(height: h);

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', ''));

/// Text field with a suggestion list (saved places plus built-in cities).
class PlaceField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final List<String> Function() options;
  const PlaceField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.options,
  });

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final FocusNode _node = FocusNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _node,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        final hits = widget
            .options()
            .where((o) => o.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) {
            final sa = a.toLowerCase().startsWith(q) ? 0 : 1;
            final sb = b.toLowerCase().startsWith(q) ? 0 : 1;
            return sa != sb ? sa - sb : a.compareTo(b);
          });
        return hits.take(8);
      },
      fieldViewBuilder: (context, ctrl, node, onSubmit) => TextField(
        controller: ctrl,
        focusNode: node,
        textCapitalization: TextCapitalization.words,
        decoration:
            InputDecoration(labelText: widget.label, prefixIcon: Icon(widget.icon)),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 260,
              maxWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a recovery code once and makes the owner confirm they saved it.
Future<void> showRecoveryCodeDialog(BuildContext context, String code) {
  var saved = false;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Your recovery code'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Write this down and keep it somewhere safe. If you forget your '
            'password, this code is the only way to open your data. It is '
            'shown once and cannot be looked up later.',
          ),
          gap(12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.line),
            ),
            child: SelectableText(code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ),
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: saved,
            onChanged: (v) => setD(() => saved = v ?? false),
            title: const Text('I have saved this code'),
          ),
        ]),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: saved ? () => Navigator.pop(c) : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}
