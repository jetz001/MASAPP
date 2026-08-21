import 'dart:async';
import 'dart:typed_data';
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
  final List<String> reasoningSteps;
  final String? reasoningContent;
  final DateTime createdAt;
  final bool isLoading;
  final bool isError;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoningSteps = const [],
    this.reasoningContent,
    required this.createdAt,
    this.isLoading = false,
    this.isError = false,
  });

  ChatMessage copyWith({
    String? content,
    List<String>? reasoningSteps,
    String? reasoningContent,
    bool? isLoading,
    bool? isError,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        reasoningSteps: reasoningSteps ?? this.reasoningSteps,
        reasoningContent: reasoningContent ?? this.reasoningContent,
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
    await ensureTable();
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
    List<AiAttachment> attachments = const [],
    List<Uint8List> imageBytesList = const [],
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

    final initialSteps = <String>['กำลังวิเคราะห์คำถามและบริบท...'];
    var currentReasoning = '';

    final loadingMsg = ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.assistant,
      content: '',
      reasoningSteps: List<String>.from(initialSteps),
      createdAt: DateTime.now(),
      isLoading: true,
    );

    state = state.copyWith(messages: [...state.messages, userMsg, loadingMsg]);

    // Save user message to DB
    await _saveToDb(state.sessionId, 'user', displayed, userId: userId);

    void updateProgress({String? newStep, String? reasoningChunk}) {
      if (newStep != null && !initialSteps.contains(newStep)) {
        initialSteps.add(newStep);
      }
      if (reasoningChunk != null) {
        currentReasoning += reasoningChunk;
      }
      final updatedMessages = state.messages.map((m) {
        if (m.id == loadingMsg.id) {
          return m.copyWith(
            reasoningSteps: List<String>.from(initialSteps),
            reasoningContent: currentReasoning.isNotEmpty ? currentReasoning : null,
          );
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updatedMessages);
    }

    try {
      final config = await AiService.loadConfig();
      if (!config.isComplete) {
        throw Exception('ยังไม่ได้ตั้งค่า AI Provider หรือ API Key');
      }

      final chatResult = await AiService.chat(
        config: config,
        history: List<AiConversationMessage>.from(_history),
        userMessage: userText.trim(),
        attachments: attachments,
        imageBytesList: imageBytesList,
        onReasoningStep: (step) => updateProgress(newStep: step),
        onReasoningChunk: (chunk) => updateProgress(reasoningChunk: chunk),
      );

      final responseText = chatResult.text;
      final finalSteps = chatResult.reasoningSteps.isNotEmpty
          ? chatResult.reasoningSteps
          : initialSteps;
      final finalReasoning = chatResult.reasoningContent ??
          (currentReasoning.isNotEmpty ? currentReasoning : null);

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
          return m.copyWith(
            content: responseText,
            reasoningSteps: finalSteps,
            reasoningContent: finalReasoning,
            isLoading: false,
          );
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
      String rawMsg = e.toString().replaceFirst('Exception: ', '');
      if (e is TimeoutException || rawMsg.contains('TimeoutException') || rawMsg.contains('timed out')) {
        rawMsg = 'การประมวลผลใช้เวลานานเกินกำหนด (Timeout) เนื่องจากเอกสารมีขนาดใหญ่หรือโมเดล AI กำลังประมวลผลข้อมูลจำนวนมาก กรุณาลองส่งใหม่อีกครั้งครับ';
      }
      final errMsg = 'เกิดข้อผิดพลาด: $rawMsg';
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

  /// Start a new chat session
  void newChat() {
    _history.clear();
    state = AiChatState(
      sessionId: const Uuid().v4(),
      messages: [],
      isConfigured: state.isConfigured,
      isModelReady: state.isModelReady,
    );
  }

  /// Clear current chat messages
  void clearChat() {
    newChat();
  }

  static bool _tableEnsured = false;

  /// Ensure the ai_chat_history table exists in SQLite database
  static Future<void> ensureTable() async {
    if (_tableEnsured) return;
    try {
      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS ai_chat_history (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id  TEXT NOT NULL,
          user_id     TEXT,
          role        TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'tool')),
          content     TEXT NOT NULL,
          tool_calls  TEXT,
          created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
      ''');
      await DbHelper.execute('''
        CREATE INDEX IF NOT EXISTS idx_ai_chat_session ON ai_chat_history(session_id, created_at);
      ''');
      _tableEnsured = true;
    } catch (_) {}
  }

  /// Load historical chat sessions summary list
  static Future<List<ChatSessionSummary>> getChatSessions() async {
    try {
      await ensureTable();
      final rows = await DbHelper.query('''
        SELECT session_id,
               MIN(created_at) as created_at,
               MAX(created_at) as updated_at,
               COUNT(*) as message_count,
               (SELECT content FROM ai_chat_history h2 WHERE h2.session_id = h1.session_id AND role = 'user' ORDER BY id ASC LIMIT 1) as first_user_msg,
               (SELECT content FROM ai_chat_history h3 WHERE h3.session_id = h1.session_id ORDER BY id DESC LIMIT 1) as last_msg
        FROM ai_chat_history h1
        GROUP BY session_id
        ORDER BY updated_at DESC
      ''');
      return rows.map((r) => ChatSessionSummary.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Load a past conversation session into state to continue chatting
  Future<void> loadSession(String sessionId) async {
    try {
      await ensureTable();
      final rows = await DbHelper.query('''
        SELECT id, session_id, role, content, created_at
        FROM ai_chat_history
        WHERE session_id = @sid
        ORDER BY id ASC
      ''', params: {'sid': sessionId});

      _history.clear();
      final loadedMessages = <ChatMessage>[];

      for (final r in rows) {
        final roleStr = r['role']?.toString().toLowerCase().trim();
        final content = r['content']?.toString() ?? '';
        final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now();

        if (roleStr == 'user') {
          _history.add(AiConversationMessage(role: 'user', content: content));
          loadedMessages.add(ChatMessage(
            id: 'msg_${r['id']}',
            role: ChatRole.user,
            content: content,
            createdAt: createdAt,
          ));
        } else if (roleStr == 'assistant') {
          _history.add(AiConversationMessage(role: 'assistant', content: content));
          loadedMessages.add(ChatMessage(
            id: 'msg_${r['id']}',
            role: ChatRole.assistant,
            content: content,
            createdAt: createdAt,
          ));
        }
      }

      state = AiChatState(
        sessionId: sessionId,
        messages: loadedMessages,
        isConfigured: state.isConfigured,
        isModelReady: state.isModelReady,
      );
    } catch (_) {}
  }

  /// Delete an entire conversation session
  Future<void> deleteSession(String sessionId) async {
    try {
      await ensureTable();
      await DbHelper.execute(
        'DELETE FROM ai_chat_history WHERE session_id = @sid',
        params: {'sid': sessionId},
      );
      if (state.sessionId == sessionId) {
        newChat();
      }
    } catch (_) {}
  }

  Future<void> _saveToDb(
    String sessionId,
    String role,
    String content, {
    String? userId,
  }) async {
    try {
      await ensureTable();
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

// ── Chat Session Summary Model ──────────────────────────────────────────────

class ChatSessionSummary {
  final String sessionId;
  final String title;
  final String lastMessage;
  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatSessionSummary({
    required this.sessionId,
    required this.title,
    required this.lastMessage,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSessionSummary.fromMap(Map<String, dynamic> map) {
    final firstUserMsg = map['first_user_msg']?.toString() ?? '';
    final lastMsg = map['last_msg']?.toString() ?? '';

    // Clean title from first user message
    String cleanTitle = firstUserMsg;
    if (cleanTitle.contains('📎 [แนบ')) {
      final lines = cleanTitle.split('\n');
      final promptLine = lines.firstWhere(
        (l) => !l.startsWith('📎 [แนบ') && l.trim().isNotEmpty,
        orElse: () => lines.first,
      );
      cleanTitle = promptLine.trim();
    }
    if (cleanTitle.length > 60) {
      cleanTitle = '${cleanTitle.substring(0, 57)}...';
    }
    if (cleanTitle.isEmpty) {
      cleanTitle = 'การสนทนา (${map['session_id'].toString().substring(0, 8)})';
    }

    return ChatSessionSummary(
      sessionId: map['session_id']?.toString() ?? '',
      title: cleanTitle,
      lastMessage: lastMsg.length > 80 ? '${lastMsg.substring(0, 77)}...' : lastMsg,
      messageCount: (map['message_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

// ── Providers ───────────────────────────────────────────────────────────────

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((
  ref,
) {
  return AiChatNotifier();
});

final chatSessionsProvider = FutureProvider.autoDispose<List<ChatSessionSummary>>((ref) async {
  return await AiChatNotifier.getChatSessions();
});
