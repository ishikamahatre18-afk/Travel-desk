import 'dart:math' as math;

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

// ---------------------------------------------------------------- brand & motion

/// The app mark: a chat bubble holding a compass needle. The same artwork is
/// used for the launcher icon.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF167C7C), Color(0xFF08343A)],
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF08343A).withValues(alpha: 0.22),
              blurRadius: size * 0.35,
              offset: Offset(0, size * 0.12),
            ),
          ],
        ),
        child: CustomPaint(painter: _MarkPainter()),
      );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2, cy = s / 2 - s * 0.015;
    final r = s * 0.30;
    final white = Paint()..color = Colors.white;
    final tail = Path()
      ..moveTo(cx - r * 0.78, cy + r * 0.55)
      ..lineTo(cx - r * 1.02, cy + r * 1.10)
      ..lineTo(cx - r * 0.18, cy + r * 0.93)
      ..close();
    canvas.drawPath(tail, white);
    canvas.drawCircle(Offset(cx, cy), r, white);
    final r2 = r * 0.80;
    const deep = Color(0xFF0E5C60);
    canvas.drawCircle(Offset(cx, cy), r2, Paint()..color = deep);

    final len = r2 * 0.86, w = r2 * 0.26;
    const ang = 40 * 3.1415926535 / 180;
    Offset rot(double x, double y) => Offset(
          cx + x * math.cos(ang) - y * math.sin(ang),
          cy + x * math.sin(ang) + y * math.cos(ang),
        );
    Path tri(Offset a, Offset b, Offset c) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(tri(rot(0, len), rot(-w, 0), rot(w, 0)), Paint()..color = const Color(0xFFD6E8E6));
    canvas.drawPath(tri(rot(0, -len), rot(-w, 0), rot(w, 0)), Paint()..color = const Color(0xFFF4C478));
    canvas.drawCircle(Offset(cx, cy), w * 0.34, Paint()..color = deep);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Fades and slides its child in once. Used for chat bubbles and chips.
class Appear extends StatefulWidget {
  final Widget child;
  final bool animate;
  final Duration delay;
  final Offset from;
  const Appear({
    super.key,
    required this.child,
    this.animate = true,
    this.delay = Duration.zero,
    this.from = const Offset(0, 12),
  });

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: AnimatedBuilder(
          animation: _a,
          builder: (c, ch) => Transform.translate(
            offset: Offset(widget.from.dx * (1 - _a.value), widget.from.dy * (1 - _a.value)),
            child: ch,
          ),
          child: widget.child,
        ),
      );
}

/// Three softly pulsing dots: "the assistant is thinking".
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});
  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (c, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1F8A8A).withValues(
                    alpha: 0.25 + 0.65 * math.pow(math.sin((_c.value * 2 * math.pi) - i * 0.9).clamp(0.0, 1.0), 2).toDouble()),
              ),
            ),
        ]),
      );
}

/// Small animated bars shown while the assistant is speaking.
class SpeakingBars extends StatefulWidget {
  const SpeakingBars({super.key});
  @override
  State<SpeakingBars> createState() => _SpeakingBarsState();
}

class _SpeakingBarsState extends State<SpeakingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (c, _) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.only(right: 2.5),
              width: 3,
              height: 5 + 9 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi + i * 1.3)),
              decoration: BoxDecoration(
                color: const Color(0xFF1F8A8A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ]),
      );
}
