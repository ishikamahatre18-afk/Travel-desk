import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// The assistant's voice. It uses the phone's own text-to-speech engine, so it
/// works offline once a voice is installed. It picks a male voice when the
/// phone has one and lowers the pitch for a deep, steady tone.
class Voice extends ChangeNotifier {
  Voice._();
  static final Voice instance = Voice._();

  static const _key = 'voice_on';
  final FlutterTts _tts = FlutterTts();
  static const _store = FlutterSecureStorage();

  bool enabled = true;
  bool speaking = false;
  bool _ready = false;
  bool _starting = false;

  Future<void> init() async {
    if (_ready || _starting) return;
    _starting = true;
    try {
      try {
        enabled = (await _store.read(key: _key)) != 'off';
      } catch (_) {}
      await _tts.awaitSpeakCompletion(true);
      var ok = await _tts.setLanguage('en-IN');
      if (ok != 1) await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(0.62);
      await _tts.setVolume(1.0);
      await _pickVoice();
      _tts.setStartHandler(() => _mark(true));
      _tts.setCompletionHandler(() => _mark(false));
      _tts.setCancelHandler(() => _mark(false));
      _tts.setErrorHandler((_) => _mark(false));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    _starting = false;
    notifyListeners();
  }

  void _mark(bool v) {
    if (speaking == v) return;
    speaking = v;
    notifyListeners();
  }

  Future<void> _pickVoice() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;
      Map<String, String>? best;
      var bestScore = -1;
      for (final v in raw) {
        if (v is! Map) continue;
        final name = (v['name'] ?? '').toString();
        final locale = (v['locale'] ?? '').toString();
        final low = name.toLowerCase();
        if (!locale.toLowerCase().startsWith('en')) continue;
        var score = 0;
        if (low.contains('male') && !low.contains('female')) score += 6;
        if (low.contains('local') || !low.contains('network')) score += 3;
        if (locale.toLowerCase().contains('in')) score += 2;
        if (locale.toLowerCase().contains('gb')) score += 1;
        if (low.contains('female')) score -= 4;
        if (score > bestScore) {
          bestScore = score;
          best = {'name': name, 'locale': locale};
        }
      }
      if (best != null) await _tts.setVoice(best);
    } catch (_) {}
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    if (!v) await stop();
    try {
      await _store.write(key: _key, value: v ? 'on' : 'off');
    } catch (_) {}
    notifyListeners();
  }

  /// Plain text only: markdown marks, links and symbols are removed so the
  /// voice reads naturally.
  static String clean(String t) {
    var s = t
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll('₹', ' rupees ')
        .replaceAll(RegExp(r'[*_#`>•→]+'), ' ')
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length > 480) {
      final cut = s.lastIndexOf(RegExp(r'[.!?]'), 480);
      s = cut > 120 ? s.substring(0, cut + 1) : s.substring(0, 480);
    }
    return s;
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    if (!_ready) await init();
    if (!_ready) return;
    final s = clean(text);
    if (s.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(s);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _mark(false);
  }
}
