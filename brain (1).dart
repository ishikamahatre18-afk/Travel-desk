import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:path_provider/path_provider.dart';

import 'agent.dart';
import 'downloader.dart';

enum BrainState { checking, notInstalled, downloading, loading, ready, error }

/// A model the owner can install. Both are open-licence, run fully on the phone,
/// and are downloaded by the app's own resumable downloader.
class ModelChoice {
  final String id, title, blurb, url, file;
  final int approxBytes;
  const ModelChoice({
    required this.id,
    required this.title,
    required this.blurb,
    required this.url,
    required this.file,
    required this.approxBytes,
  });
}

const kLightModel = ModelChoice(
  id: 'light',
  title: 'Faster download (1.25 GB)',
  blurb: 'Recommended. Quick to install and quick to answer.',
  url: 'https://huggingface.co/litert-community/LFM2.5-1.2B-Instruct/resolve/main/LFM2.5-1.2B-Instruct_int8.litertlm',
  file: 'LFM2.5-1.2B-Instruct_int8.litertlm',
  approxBytes: 1250000000,
);

const kSmartModel = ModelChoice(
  id: 'smart',
  title: 'Smarter, larger (2.6 GB)',
  blurb: 'Better answers, but a longer download and slower replies.',
  url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  file: 'gemma-4-E2B-it.litertlm',
  approxBytes: 2583000000,
);

const kModels = [kLightModel, kSmartModel];

/// The on-device language model. After the one-time download it runs entirely
/// on the phone: no server, no account, nothing leaves the device.
class Brain extends ChangeNotifier implements Llm {
  Brain._();
  static final Brain instance = Brain._();

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
  Timer? _tick;
  bool _working = false;

  dynamic _model;
  dynamic _chat;

  // ------------------------------------------------------ progress read-outs

  Duration get elapsed => DateTime.now().difference(_phaseStart);
  Duration get sinceProgress => DateTime.now().difference(_lastProgressAt);

  ModelChoice? choice; // what is being (or was last) downloaded
  int bytesDone = 0;
  int bytesTotal = 0;
  String? note; // e.g. "Connection dropped. Continuing…"
  double _bytesPerSec = 0; // smoothed
  final Map<String, int> partial = {}; // choice id -> bytes already on disk

  double? get downloadedMb => bytesTotal > 0 ? bytesDone / 1e6 : null;
  double? get totalMb => bytesTotal > 0 ? bytesTotal / 1e6 : null;

  /// Smoothed speed in MB per second.
  double? get speedMbPerSec => _bytesPerSec > 50000 ? _bytesPerSec / 1e6 : null;

  Duration? get eta {
    if (_bytesPerSec <= 50000 || bytesTotal <= 0 || bytesDone >= bytesTotal) return null;
    return Duration(seconds: ((bytesTotal - bytesDone) / _bytesPerSec).round());
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

  DateTime _lastSample = DateTime.now();
  int _lastSampleBytes = 0;

  void _onBytes(int done, int total) {
    final now = DateTime.now();
    bytesDone = done;
    bytesTotal = total;
    progress = total > 0 ? (done * 100 ~/ total).clamp(0, 100) : 0;
    final dt = now.difference(_lastSample).inMilliseconds;
    if (dt >= 1000) {
      final inst = (done - _lastSampleBytes) * 1000 / dt;
      if (inst >= 0) _bytesPerSec = _bytesPerSec == 0 ? inst : _bytesPerSec * 0.7 + inst * 0.3;
      if (done > _lastSampleBytes) _lastProgressAt = now;
      _lastSample = now;
      _lastSampleBytes = done;
      note = null;
      notifyListeners();
    }
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
      final m = await FlutterEdgeAi.getActiveModel(maxTokens: 3072).timeout(loadTimeout);
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

  Future<Directory> _modelDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/models');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Bytes already downloaded for each model (so the screen can say "resume").
  Future<void> scanPartials() async {
    try {
      final d = await _modelDir();
      for (final m in kModels) {
        final f = File('${d.path}/${m.file}.part');
        partial[m.id] = f.existsSync() ? f.lengthSync() : 0;
      }
      notifyListeners();
    } catch (_) {}
  }

  ResumableDownload? _dl;

  /// One-time download. Needs internet only for this step. It resumes after any
  /// interruption, including closing the app, instead of starting from zero.
  Future<void> install([ModelChoice? pick]) async {
    if (_working || state == BrainState.downloading) return;
    _working = true;
    final my = ++_gen; // cancels any slow check still running
    final m = pick ?? choice ?? kLightModel;
    choice = m;
    progress = 0;
    bytesDone = 0;
    bytesTotal = m.approxBytes;
    _bytesPerSec = 0;
    _lastSample = DateTime.now();
    _lastSampleBytes = 0;
    _lastProgressAt = DateTime.now();
    note = null;
    step = 'Starting the download…';
    _set(BrainState.downloading);
    try {
      if (initError != null) throw 'the AI engine did not start ($initError)';
      final dir = await _modelDir();
      final part = File('${dir.path}/${m.file}.part');
      final final_ = File('${dir.path}/${m.file}');

      // Enough room? (needs the rest of the file plus a little spare)
      final dl = _dl = ResumableDownload(url: m.url, part: part, expectedBytes: m.approxBytes);
      _lastSampleBytes = dl.have;
      bytesDone = dl.have;
      await dl.run(
        onProgress: _onBytes,
        onNote: (n) {
          note = n;
          notifyListeners();
        },
      );
      if (part.existsSync()) {
        if (final_.existsSync()) final_.deleteSync();
        part.renameSync(final_.path);
      }
      progress = 100;
      step = 'Download complete. Installing…';
      _set(BrainState.loading);
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(final_.path).install();
      step = 'Loading into memory…';
      notifyListeners();
      final model = await FlutterEdgeAi.getActiveModel(maxTokens: 3072).timeout(loadTimeout);
      if (my != _gen) return;
      _model = model;
      step = 'Ready';
      _set(BrainState.ready);
    } on TimeoutException {
      _set(BrainState.error,
          err: 'The download finished, but loading the assistant took more than '
              '${loadTimeout.inMinutes} minutes. Close other apps and try again.');
    } catch (e) {
      _set(BrainState.error,
          err: 'The download did not finish: $e\n'
              'Your progress is saved. Check the internet and free storage, then tap Try again to continue.');
    } finally {
      _dl = null;
      _working = false;
      scanPartials();
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
