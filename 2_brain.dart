import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'agent.dart';

enum BrainState { checking, notInstalled, downloading, loading, ready, error }

/// The on-device language model. After the one-time download it runs entirely
/// on the phone: no server, no account, nothing leaves the device.
class Brain extends ChangeNotifier implements Llm {
  Brain._();
  static final Brain instance = Brain._();

  /// Optional: your own hosted Gemma-family `.litertlm` file. Leave empty to
  /// use the built-in catalog model.
  static const modelUrl = String.fromEnvironment('MODEL_URL');

  /// Approximate size of the built-in catalog model (Gemma 4 E2B), in MB.
  /// Used only to show "x of y" while downloading.
  static const approxModelMb = 2580;

  /// Loading a model into memory the first time can be slow on some phones.
  static const loadTimeout = Duration(minutes: 10);

  /// Set when the AI engine could not start. Shown to the owner.
  static String? initError;

  static Future<void> initialize() async {
    try {
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
        huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN').isEmpty
            ? null
            : const String.fromEnvironment('HUGGINGFACE_TOKEN'),
      ).timeout(const Duration(seconds: 30));
      initError = null;
    } catch (e) {
      initError = '$e';
    }
  }

  BrainState state = BrainState.checking;
  int progress = 0; // percent, 0..100
  String? error;

  /// A plain-words description of what the assistant is doing right now.
  String step = 'Starting…';

  DateTime _phaseStart = DateTime.now();
  DateTime _lastProgressAt = DateTime.now();
  double _percentPerSec = 0; // smoothed
  Timer? _tick;
  bool _working = false;

  dynamic _model;
  dynamic _chat;

  // ------------------------------------------------------ progress read-outs

  Duration get elapsed => DateTime.now().difference(_phaseStart);
  Duration get sinceProgress => DateTime.now().difference(_lastProgressAt);

  /// Megabytes downloaded so far, estimated from the percentage.
  double? get downloadedMb => modelUrl.isEmpty ? progress * approxModelMb / 100 : null;
  double? get totalMb => modelUrl.isEmpty ? approxModelMb.toDouble() : null;

  /// Smoothed speed in MB per second, once enough has been seen.
  double? get speedMbPerSec {
    final total = totalMb;
    if (total == null || _percentPerSec <= 0) return null;
    return _percentPerSec * total / 100;
  }

  Duration? get eta {
    if (_percentPerSec <= 0 || progress <= 0 || progress >= 100) return null;
    return Duration(seconds: ((100 - progress) / _percentPerSec).round());
  }

  /// True when the download has not moved for a while.
  bool get stalled =>
      state == BrainState.downloading && sinceProgress > const Duration(seconds: 90);

  void _set(BrainState s, {String? err}) {
    state = s;
    error = err;
    _phaseStart = DateTime.now();
    _tick?.cancel();
    if (s == BrainState.downloading || s == BrainState.loading || s == BrainState.checking) {
      // A one-second heartbeat keeps the elapsed time on screen moving, so the
      // owner can always see the app is alive.
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    }
    notifyListeners();
  }

  void _onProgress(int p) {
    final now = DateTime.now();
    final v = p.clamp(0, 100);
    final dt = now.difference(_lastProgressAt).inMilliseconds / 1000.0;
    if (v > progress && dt > 0) {
      final inst = (v - progress) / dt;
      _percentPerSec = _percentPerSec == 0 ? inst : _percentPerSec * 0.8 + inst * 0.2;
    }
    if (v != progress) _lastProgressAt = now;
    progress = v;
    notifyListeners();
  }

  // -------------------------------------------------------------- lifecycle

  int _gen = 0; // lets a newer action ignore the result of an older one

  /// Looks for an installed model and loads it into memory.
  Future<void> check() async {
    if (state == BrainState.ready) return;
    final my = ++_gen;
    _set(BrainState.checking);
    if (initError != null) {
      step = 'Engine start failed';
      _set(BrainState.error, err: 'The AI engine could not start: $initError');
      return;
    }
    try {
      step = 'Looking for an installed assistant…';
      notifyListeners();
      final m = await FlutterEdgeAi.getActiveModel(maxTokens: 4096).timeout(loadTimeout);
      if (my != _gen) return;
      _model = m;
      step = 'Ready';
      _set(BrainState.ready);
    } on StateError {
      if (my != _gen) return;
      // No model installed yet: the one-time download is next.
      step = 'No assistant installed yet';
      _set(BrainState.notInstalled);
    } on TimeoutException {
      if (my != _gen) return;
      _set(BrainState.error,
          err: 'Loading the assistant took more than ${loadTimeout.inMinutes} minutes. '
              'Close other apps to free memory, then try again.');
    } catch (e) {
      if (my != _gen) return;
      _set(BrainState.error, err: 'The assistant could not start: $e');
    }
  }

  /// One-time download. Needs internet only for this step.
  Future<void> install() async {
    if (_working || state == BrainState.downloading) return;
    _working = true;
    final my = ++_gen; // cancels any slow check still running
    progress = 0;
    _percentPerSec = 0;
    _lastProgressAt = DateTime.now();
    step = 'Starting the download…';
    _set(BrainState.downloading);
    try {
      if (initError != null) throw 'the AI engine did not start ($initError)';
      if (modelUrl.isEmpty) {
        await FlutterEdgeAi.installModelFromCatalog(LiteRtLmModels.gemma4E2bIt.generic)
            .withProgress(_onProgress)
            .install();
      } else {
        await FlutterEdgeAi.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
        ).fromNetwork(modelUrl).withProgress(_onProgress).install();
      }
      progress = 100;
      step = 'Download complete. Loading into memory…';
      _set(BrainState.loading);
      final m = await FlutterEdgeAi.getActiveModel(maxTokens: 4096).timeout(loadTimeout);
      if (my != _gen) return;
      _model = m;
      step = 'Ready';
      _set(BrainState.ready);
    } on TimeoutException {
      _set(BrainState.error,
          err: 'The download finished, but loading the assistant took more than '
              '${loadTimeout.inMinutes} minutes. Close other apps and try again.');
    } catch (e) {
      _set(BrainState.error,
          err: 'The download did not finish: $e\n'
              'Check the internet connection and free storage space, then try again.');
    } finally {
      _working = false;
    }
  }

  /// Tries again after an error. If the model is already downloaded this only
  /// reloads it; otherwise it starts the download again.
  Future<void> retry() async {
    if (_working) return;
    await check();
    if (state == BrainState.notInstalled) await install();
  }

  // ------------------------------------------------------------------- chat

  /// Starts a fresh conversation, so the model forgets the previous turns.
  @override
  Future<void> newChat() async {
    if (_model == null) throw StateError('The assistant is not ready.');
    try {
      await _chat?.close();
    } catch (_) {}
    _chat = await _model.openChat();
  }

  /// Drops the conversation from memory (called when the app locks).
  Future<void> resetChat() async {
    final c = _chat;
    _chat = null;
    try {
      await c?.close();
    } catch (_) {}
  }

  bool get hasChat => _chat != null;

  /// Sends one message and returns the whole reply. [onText] receives the
  /// reply so far, for live typing.
  @override
  Future<String> send(String text, {void Function(String soFar)? onText}) async {
    if (_chat == null) await newChat();
    await _chat.addQueryChunk(Message.text(text: text, isUser: true));
    final buf = StringBuffer();
    await for (final r in _chat.generateChatResponseAsync()) {
      if (r is TextResponse) {
        buf.write(r.token);
        onText?.call(buf.toString());
      }
    }
    return buf.toString();
  }
}
