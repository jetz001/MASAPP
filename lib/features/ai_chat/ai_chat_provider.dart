// lib/features/ai_chat/ai_chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/ai/ai_service.dart';
import '../../core/database/db_helper.dart';

// ── Message model ───────────────────────────────────────────────────────────

enum ChatRole { user, assistant, thinking }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final bool isLoading;
  final bool isError;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isLoading = false,
    this.isError = false,
  });

  ChatMessage copyWith({String? content, bool? isLoading, bool? isError}) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        isLoading: isLoading ?? this.isLoading,
        isError: isError ?? this.isError,
      );
}

// ── Chat state ──────────────────────────────────────────────────────────────

class AiChatState {
  final List<ChatMessage> messages;
  final bool isModelReady;
  final bool isConfigured;
  final String sessionId;

  const AiChatState({
    this.messages = const [],
    this.isModelReady = false,
    this.isConfigured = false,
    required this.sessionId,
  });

  AiChatState copyWith({
    List<ChatMessage>? messages,
    bool? isModelReady,
    bool? isConfigured,
  }) => AiChatState(
    messages: messages ?? this.messages,
    isModelReady: isModelReady ?? this.isModelReady,
    isConfigured: isConfigured ?? this.isConfigured,
    sessionId: sessionId,
  );
}

// ── Notifier ────────────────────────────────────────────────────────────────

class AiChatNotifier extends StateNotifier<AiChatState> {
  final List<AiConversationMessage> _history = [];

  AiChatNotifier() : super(AiChatState(sessionId: const Uuid().v4())) {
    _init();
  }

  Future<void> _init() async {
    final configured = await AiService.isConfigured();
    state = state.copyWith(isConfigured: configured, isModelReady: configured);
  }

  /// Reload chat capability after AI config changes
  Future<void> reloadModel() async {
    final configured = await AiService.isConfigured();
    state = state.copyWith(isConfigured: configured, isModelReady: configured);
  }

  /// Send a user message and get AI response
  Future<void> sendMessage(
    String userText, {
    String? displayText,
    String? userId,
  }) async {
    if (userText.trim().isEmpty) return;

    final displayed = (displayText != null && displayText.trim().isNotEmpty)
        ? displayText.trim()
        : userText.trim();

    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.user,
      content: displayed,
      createdAt: DateTime.now(),
    );

    final loadingMsg = ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      isLoading: true,
    );

    state = state.copyWith(messages: [...state.messages, userMsg, loadingMsg]);

    // Save user message to DB
    await _saveToDb(state.sessionId, 'user', displayed, userId: userId);

    try {
      final config = await AiService.loadConfig();
      if (!config.isComplete) {
        throw Exception('ยังไม่ได้ตั้งค่า AI Provider หรือ API Key');
      }

      final responseText = await AiService.chat(
        config: config,
        history: List<AiConversationMessage>.from(_history),
        userMessage: userText.trim(),
      );

      // Update history for next turn
      _history.add(
        AiConversationMessage(role: 'user', content: userText.trim()),
      );
      _history.add(
        AiConversationMessage(role: 'assistant', content: responseText),
      );

      // Replace loading bubble with real response
      final updatedMessages = state.messages.map((m) {
        if (m.id == loadingMsg.id) {
          return m.copyWith(content: responseText, isLoading: false);
        }
        return m;
      }).toList();

      state = state.copyWith(messages: updatedMessages);
      await _saveToDb(
        state.sessionId,
        'assistant',
        responseText,
        userId: userId,
      );
    } catch (e) {
      final errMsg =
          'เกิดข้อผิดพลาด: ${e.toString().replaceFirst('Exception: ', '')}';
      final updatedMessages = state.messages.map((m) {
        if (m.id == loadingMsg.id) {
          return m.copyWith(content: errMsg, isLoading: false, isError: true);
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updatedMessages);
    }
  }

  /// Add assistant message directly (e.g. after RAG upload notification)
  Future<void> addAssistantMessage(String text, {String? userId}) async {
    final msg = ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.assistant,
      content: text,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, msg]);
    _history.add(AiConversationMessage(role: 'assistant', content: text));
    await _saveToDb(state.sessionId, 'assistant', text, userId: userId);
  }

  /// Clear chat history
  void clearChat() {
    _history.clear();
    state = AiChatState(
      sessionId: const Uuid().v4(),
      isConfigured: state.isConfigured,
      isModelReady: state.isModelReady,
    );
  }

  Future<void> _saveToDb(
    String sessionId,
    String role,
    String content, {
    String? userId,
  }) async {
    try {
      await DbHelper.execute(
        '''INSERT INTO ai_chat_history(session_id, user_id, role, content)
           VALUES(@sid, @uid, @role, @content)''',
        params: {
          'sid': sessionId,
          'uid': userId,
          'role': role,
          'content': content,
        },
      );
    } catch (_) {}
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((
  ref,
) {
  return AiChatNotifier();
});
