import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:sage/core/services/chat_persistence.dart';
import 'package:sage/core/theme/theme_provider.dart';
import 'package:sage/features/chat/data/chat_repository.dart';
import 'package:sage/features/chat/models/chat_models.dart';

String _friendlyError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out. Check your network.';
      case DioExceptionType.connectionError:
        return 'Cannot reach the server. Check your connection.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401 || code == 403)
          return 'Session expired. Please sign in again.';
        if (code == 503) return 'Service temporarily unavailable.';
        return 'Server error. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

// ═══════════════════════════════════════════════════════════════
// Chat State
// ═══════════════════════════════════════════════════════════════

class ChatState {
  final List<ChatMessage> messages;
  final String? conversationId;
  final String conversationType;
  final bool isLoading;
  final bool isRecording;
  final bool isTranscribing;
  final String? error;
  final StrategyParams? latestParams;

  /// Transcript awaiting user review before sending.
  final String? pendingTranscript;

  const ChatState({
    this.messages = const [],
    this.conversationId,
    this.conversationType = 'general',
    this.isLoading = false,
    this.isRecording = false,
    this.isTranscribing = false,
    this.error,
    this.latestParams,
    this.pendingTranscript,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? conversationId,
    String? conversationType,
    bool? isLoading,
    bool? isRecording,
    bool? isTranscribing,
    String? error,
    StrategyParams? latestParams,
    String? pendingTranscript,
    bool clearError = false,
    bool clearParams = false,
    bool clearPendingTranscript = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      conversationId: conversationId ?? this.conversationId,
      conversationType: conversationType ?? this.conversationType,
      isLoading: isLoading ?? this.isLoading,
      isRecording: isRecording ?? this.isRecording,
      isTranscribing: isTranscribing ?? this.isTranscribing,
      error: clearError ? null : (error ?? this.error),
      latestParams: clearParams ? null : (latestParams ?? this.latestParams),
      pendingTranscript: clearPendingTranscript
          ? null
          : (pendingTranscript ?? this.pendingTranscript),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Chat Notifier (general / portfolio)
// ═══════════════════════════════════════════════════════════════

class ChatNotifier extends Notifier<ChatState> {
  late final AudioRecorder _recorder;

  @override
  ChatState build() {
    _recorder = AudioRecorder();
    ref.onDispose(() => _recorder.dispose());
    // Start on the conversations list — user taps to open one.
    return const ChatState(conversationType: 'general');
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  ChatPersistence get _persistence => ref.read(chatPersistenceProvider);

  /// Send a text message to Sage AI.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isLoading) return;

    final userMsg = ChatMessage(
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      clearError: true,
    );

    try {
      // Use latestParams if still visible, otherwise pull from the
      // last message that carried params (covers the dismissed-card case).
      final effectiveParams = state.latestParams ?? _lastKnownParams();

      final result = await _repo.sendMessage(
        message: text.trim(),
        conversationId: state.conversationId,
        type: state.conversationType,
        currentParams: effectiveParams,
      );

      final assistantMsg = ChatMessage(
        role: 'assistant',
        content: result.message,
        timestamp: DateTime.now(),
        strategyParams: result.strategyParams,
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        conversationId: result.conversationId,
        isLoading: false,
        latestParams: result.strategyParams,
      );

      // Persist the conversation ID (local cache + implicitly on server).
      _persistence.saveConversationId('general', result.conversationId);

      // Process AI actions (e.g. change_theme).
      _processActions(result.actions);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
    }
  }

  /// Execute actions from the AI response.
  void _processActions(List<AppAction> actions) {
    for (final action in actions) {
      switch (action.type) {
        case 'change_theme':
          final theme = action.payload['theme'] as String?;
          if (theme != null) {
            ref.read(themeNotifierProvider.notifier).setTheme(theme);
          }
          break;
        // Future: add more action types here
      }
    }
  }

  /// Start recording voice input.
  Future<void> startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        state = state.copyWith(error: 'Microphone permission denied');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/sage_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );

      state = state.copyWith(isRecording: true, clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'Failed to start recording: $e');
    }
  }

  /// Stop recording and surface transcript for user review before sending.
  Future<void> stopRecordingForReview() async {
    try {
      final path = await _recorder.stop();
      state = state.copyWith(isRecording: false, isTranscribing: true);

      if (path == null) {
        state = state.copyWith(
          isTranscribing: false,
          error: 'No recording captured',
        );
        return;
      }

      final text = await _repo.transcribe(File(path));
      try {
        await File(path).delete();
      } catch (_) {}

      if (text.trim().isEmpty) {
        state = state.copyWith(
          isTranscribing: false,
          error: 'Could not understand audio. Please try again.',
        );
        return;
      }

      state = state.copyWith(
        isTranscribing: false,
        pendingTranscript: text.trim(),
      );
    } catch (e) {
      state = state.copyWith(
        isTranscribing: false,
        isRecording: false,
        error: 'Could not transcribe audio. Please try again.',
      );
    }
  }

  /// Confirm the reviewed transcript and send it as a message.
  Future<void> confirmTranscript(String text) async {
    state = state.copyWith(clearPendingTranscript: true);
    await sendMessage(text);
  }

  /// Discard the pending transcript without sending.
  void discardTranscript() {
    state = state.copyWith(clearPendingTranscript: true);
  }

  /// Cancel recording without sending.
  Future<void> cancelRecording() async {
    try {
      final path = await _recorder.stop();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    } catch (_) {}
    state = state.copyWith(isRecording: false);
  }

  /// Load an existing conversation.
  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final conv = await _repo.getConversation(conversationId);
      var messages = conv.messages;

      // Backward-compat: if conversation has extractedParams but no
      // individual message carries strategyParams, retroactively tag
      // the last assistant message so the "View Strategy" chip works.
      if (conv.extractedParams != null && !conv.extractedParams!.isEmpty) {
        final hasPerMessage = messages.any((m) => m.hasStrategy);
        if (!hasPerMessage) {
          messages = List.of(messages);
          for (int i = messages.length - 1; i >= 0; i--) {
            if (messages[i].isAssistant) {
              messages[i] = messages[i].withStrategyParams(
                conv.extractedParams,
              );
              break;
            }
          }
        }
      }

      state = state.copyWith(
        messages: messages,
        conversationId: conv.conversationId,
        conversationType: conv.type,
        isLoading: false,
        latestParams: conv.extractedParams,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
    }
  }

  /// Re-surface strategy params from a specific message.
  void surfaceParamsFromMessage(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    final params = state.messages[messageIndex].strategyParams;
    if (params != null && !params.isEmpty) {
      state = state.copyWith(latestParams: params);
    }
  }

  /// Find the last strategy params from any message in the conversation.
  /// Used when latestParams was dismissed but user wants to modify via chat.
  StrategyParams? _lastKnownParams() {
    for (int i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].hasStrategy) {
        return state.messages[i].strategyParams;
      }
    }
    return null;
  }

  /// Start a new conversation.
  void newConversation({String type = 'general'}) {
    _persistence.clearConversationId('general');
    state = ChatState(conversationType: type);
  }

  /// Clear error.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Clear latestParams (user dismissed the strategy card).
  void dismissParams() {
    state = state.copyWith(clearParams: true);
  }

  /// Delete a conversation from the server.
  Future<void> deleteConversation(String conversationId) async {
    try {
      await _repo.deleteConversation(conversationId);
    } catch (_) {
      // Best-effort — list will refresh regardless
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Setup Chat Notifier (strategy configuration)
// ═══════════════════════════════════════════════════════════════

class SetupChatNotifier extends Notifier<ChatState> {
  late final AudioRecorder _recorder;

  /// Simulation bankroll set by the setup screen so the AI
  /// can propose capital-coherent strategies.
  double? _simulationBalanceSOL;

  /// Tell the AI the user's simulation bankroll for capital-aware suggestions.
  void setSimulationBalance(double balance) {
    _simulationBalanceSOL = balance;
  }

  @override
  ChatState build() {
    _recorder = AudioRecorder();
    ref.onDispose(() => _recorder.dispose());
    // Kick off async restore — resume setup conversation if one exists.
    _restoreConversation();
    return const ChatState(conversationType: 'setup');
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  ChatPersistence get _persistence => ref.read(chatPersistenceProvider);

  /// Resolve the most recent setup conversation from the server
  /// (falls back to local cache if offline).
  Future<void> _restoreConversation() async {
    try {
      final savedId = await _persistence.resolveActiveConversationId('setup');
      if (savedId != null) {
        await loadConversation(savedId);
      }
    } catch (_) {
      // Silently fail — user starts a fresh setup chat
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || state.isLoading) return;

    final userMsg = ChatMessage(
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      clearError: true,
    );

    try {
      // Use latestParams if still visible, otherwise pull from the
      // last message that carried params (covers the dismissed-card case).
      final baseParams = state.latestParams ?? _lastKnownParams();

      // Ensure the simulation bankroll is always included so the AI
      // respects capital constraints when suggesting strategies.
      final effectiveParams = _simulationBalanceSOL != null
          ? (baseParams ?? const StrategyParams()).copyWith(
              simulationBalanceSOL: _simulationBalanceSOL,
            )
          : baseParams;

      final result = await _repo.sendMessage(
        message: text.trim(),
        conversationId: state.conversationId,
        type: state.conversationType,
        currentParams: effectiveParams,
      );

      final assistantMsg = ChatMessage(
        role: 'assistant',
        content: result.message,
        timestamp: DateTime.now(),
        strategyParams: result.strategyParams,
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        conversationId: result.conversationId,
        isLoading: false,
        latestParams: result.strategyParams,
      );

      // Persist conversation ID (local cache + server has it already).
      _persistence.saveConversationId('setup', result.conversationId);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
    }
  }

  Future<void> startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        state = state.copyWith(error: 'Microphone permission denied');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/sage_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
        ),
        path: path,
      );

      state = state.copyWith(isRecording: true, clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'Failed to start recording: $e');
    }
  }

  Future<void> stopRecordingForReview() async {
    try {
      final path = await _recorder.stop();
      state = state.copyWith(isRecording: false, isTranscribing: true);

      if (path == null) {
        state = state.copyWith(
          isTranscribing: false,
          error: 'No recording captured',
        );
        return;
      }

      final text = await _repo.transcribe(File(path));
      try {
        await File(path).delete();
      } catch (_) {}

      if (text.trim().isEmpty) {
        state = state.copyWith(
          isTranscribing: false,
          error: 'Could not understand audio. Please try again.',
        );
        return;
      }

      state = state.copyWith(
        isTranscribing: false,
        pendingTranscript: text.trim(),
      );
    } catch (e) {
      state = state.copyWith(
        isTranscribing: false,
        isRecording: false,
        error: 'Could not transcribe audio. Please try again.',
      );
    }
  }

  Future<void> confirmTranscript(String text) async {
    state = state.copyWith(clearPendingTranscript: true);
    await sendMessage(text);
  }

  void discardTranscript() {
    state = state.copyWith(clearPendingTranscript: true);
  }

  Future<void> cancelRecording() async {
    try {
      final path = await _recorder.stop();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    } catch (_) {}
    state = state.copyWith(isRecording: false);
  }

  Future<void> loadConversation(String conversationId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final conv = await _repo.getConversation(conversationId);
      var messages = conv.messages;

      // Backward-compat: if conversation has extractedParams but no
      // individual message carries strategyParams, retroactively tag
      // the last assistant message so the "View Strategy" chip works.
      if (conv.extractedParams != null && !conv.extractedParams!.isEmpty) {
        final hasPerMessage = messages.any((m) => m.hasStrategy);
        if (!hasPerMessage) {
          messages = List.of(messages);
          for (int i = messages.length - 1; i >= 0; i--) {
            if (messages[i].isAssistant) {
              messages[i] = messages[i].withStrategyParams(
                conv.extractedParams,
              );
              break;
            }
          }
        }
      }

      state = state.copyWith(
        messages: messages,
        conversationId: conv.conversationId,
        conversationType: conv.type,
        isLoading: false,
        latestParams: conv.extractedParams,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyError(e));
    }
  }

  void newConversation() {
    _persistence.clearConversationId('setup');
    state = const ChatState(conversationType: 'setup');
  }

  /// Re-surface strategy params from a specific message.
  void surfaceParamsFromMessage(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    final params = state.messages[messageIndex].strategyParams;
    if (params != null && !params.isEmpty) {
      state = state.copyWith(latestParams: params);
    }
  }

  /// Replace latestParams with an edited copy.
  void updateLatestParams(StrategyParams params) {
    state = state.copyWith(latestParams: params);
  }

  /// Clear latestParams (user dismissed the strategy card).
  void dismissParams() {
    state = state.copyWith(clearParams: true);
  }

  /// Find the last strategy params from any message in the conversation.
  /// Used when latestParams was dismissed but user wants to modify via chat.
  StrategyParams? _lastKnownParams() {
    for (int i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].hasStrategy) {
        return state.messages[i].strategyParams;
      }
    }
    return null;
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ═══════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════

/// Main app chat provider (portfolio/general conversations).
final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

/// Setup chat provider (for strategy configuration conversations).
/// Separate so it doesn't interfere with the main chat.
final setupChatProvider = NotifierProvider<SetupChatNotifier, ChatState>(
  SetupChatNotifier.new,
);

/// Conversation list provider.
final conversationListProvider = FutureProvider<List<ConversationSummary>>((
  ref,
) {
  return ref.read(chatRepositoryProvider).listConversations();
});

/// AI service status provider.
final aiStatusProvider = FutureProvider<AiStatus>((ref) {
  return ref.read(chatRepositoryProvider).getStatus();
});
