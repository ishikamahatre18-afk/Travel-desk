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

  static Future<void> initialize() async {
    await FlutterEdgeAi.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
      huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN').isEmpty
          ? null
          : const String.fromEnvironment('HUGGINGFACE_TOKEN'),
    );
  }

  BrainState state = BrainState.checking;
  int progress = 0;
  String? error;

  dynamic _model;
  dynamic _chat;

  void _set(BrainState s, {String? err}) {
    state = s;
    error = err;
    notifyListeners();
  }

  /// Looks for an installed model and loads it.
  Future<void> check() async {
    if (state == BrainState.ready) return;
    _set(BrainState.checking);
    try {
      _model = await FlutterEdgeAi.getActiveModel(maxTokens: 4096);
      _set(BrainState.ready);
    } on StateError {
      _set(BrainState.notInstalled);
    } catch (e) {
      _set(BrainState.error, err: 'The assistant could not start: $e');
    }
  }

  /// One-time download. Needs internet only for this step.
  Future<void> install() async {
    if (state == BrainState.downloading) return;
    progress = 0;
    _set(BrainState.downloading);
    try {
      if (modelUrl.isEmpty) {
        await FlutterEdgeAi.installModelFromCatalog(LiteRtLmModels.gemma4E2bIt.generic)
            .withProgress((p) {
          progress = p;
          notifyListeners();
        }).install();
      } else {
        await FlutterEdgeAi.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
        ).fromNetwork(modelUrl).withProgress((p) {
          progress = p;
          notifyListeners();
        }).install();
      }
      _set(BrainState.loading);
      _model = await FlutterEdgeAi.getActiveModel(maxTokens: 4096);
      _set(BrainState.ready);
    } catch (e) {
      _set(BrainState.error,
          err: 'The download did not finish: $e\nCheck the internet connection and storage space, then try again.');
    }
  }

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
