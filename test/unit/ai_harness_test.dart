import 'package:flutter_test/flutter_test.dart';
import 'package:masapp/core/ai/ai_provider_config.dart';
import 'package:masapp/core/ai/ai_service.dart';
import 'package:masapp/core/ai/ai_tool_handler.dart';

void main() {
  group('AI Harness: Provider Catalog & Config Validation', () {
    test('AiProviderCatalog registers all supported providers', () {
      final providers = AiProviderCatalog.providers;
      final ids = providers.map((p) => p.id).toSet();

      expect(ids.contains('gemini'), isTrue);
      expect(ids.contains('openai'), isTrue);
      expect(ids.contains('claude'), isTrue);
      expect(ids.contains('deepseek'), isTrue);
      expect(ids.contains('grok'), isTrue);
      expect(ids.contains('mistral'), isTrue);
      expect(ids.contains('openrouter'), isTrue);
      expect(ids.contains('ollama'), isTrue);
    });

    test('Ollama provider does not require an API key and defaults to localhost', () {
      final ollama = AiProviderCatalog.of(AiProviderKind.ollama);
      expect(ollama.requiresApiKey, isFalse);
      expect(ollama.defaultBaseUrl, equals('http://127.0.0.1:11434'));
      expect(ollama.supportsCustomBaseUrl, isTrue);

      final config = AiProviderConfig(
        provider: AiProviderKind.ollama,
        apiKey: '',
        model: 'qwen2.5:0.5b',
        baseUrl: ollama.defaultBaseUrl,
      );
      expect(config.isComplete, isTrue);
      expect(config.resolvedBaseUrl, equals('http://127.0.0.1:11434'));
    });

    test('Gemini and OpenAI providers require API keys', () {
      final geminiConfig = AiProviderConfig(
        provider: AiProviderKind.gemini,
        apiKey: '',
        model: 'gemini-1.5-flash-latest',
      );
      expect(geminiConfig.isComplete, isFalse);

      final validGemini = geminiConfig.copyWith(apiKey: 'AIzaSyFakeKey12345');
      expect(validGemini.isComplete, isTrue);

      final openaiConfig = AiProviderConfig(
        provider: AiProviderKind.openai,
        apiKey: 'sk-test-fake-key',
        model: 'gpt-4o-mini',
      );
      expect(openaiConfig.isComplete, isTrue);
      expect(openaiConfig.resolvedBaseUrl, equals('https://api.openai.com/v1'));
    });

    test('EmbeddingProviderCatalog supports local TF-IDF and Ollama nomic-embed-text', () {
      // 1. Built-in Local Offline Embedding
      final localEmbedding = EmbeddingProviderCatalog.of(EmbeddingProviderKind.local);
      expect(localEmbedding.id, equals('local'));
      expect(localEmbedding.defaultModel, equals('local-tfidf-ngram'));
      expect(localEmbedding.requiresApiKey, isFalse);

      final localConfig = EmbeddingProviderConfig(
        provider: EmbeddingProviderKind.local,
        apiKey: '',
        model: 'local-tfidf-ngram',
      );
      expect(localConfig.isComplete, isTrue);

      // 2. Ollama Local Embedding (nomic-embed-text)
      final ollamaEmbedding = EmbeddingProviderCatalog.of(EmbeddingProviderKind.ollama);
      expect(ollamaEmbedding.id, equals('ollama'));
      expect(ollamaEmbedding.defaultModel, equals('nomic-embed-text'));
      expect(ollamaEmbedding.requiresApiKey, isFalse);
      expect(ollamaEmbedding.defaultBaseUrl, equals('http://127.0.0.1:11434'));

      final ollamaConfig = EmbeddingProviderConfig(
        provider: EmbeddingProviderKind.ollama,
        apiKey: '',
        model: 'nomic-embed-text',
        baseUrl: ollamaEmbedding.defaultBaseUrl,
      );
      expect(ollamaConfig.isComplete, isTrue);
      expect(ollamaConfig.resolvedBaseUrl, equals('http://127.0.0.1:11434'));
    });
  });

  group('AI Harness: Tool Handler Security & Safety Invariants', () {
    test('query_database rejects non-SELECT statements', () async {
      final dropResult = await AiToolHandler.handleToolCall(
        'query_database',
        {'sql': 'DROP TABLE machines;'},
      );
      expect(dropResult.contains('error'), isTrue);
      expect(dropResult.contains('Only SELECT or WITH'), isTrue);

      final insertResult = await AiToolHandler.handleToolCall(
        'query_database',
        {'sql': "INSERT INTO machines (machine_id) VALUES ('MC-01');"},
      );
      expect(insertResult.contains('error'), isTrue);
    });

    test('query_database blocks access to sensitive tables', () async {
      final userQueryResult = await AiToolHandler.handleToolCall(
        'query_database',
        {'sql': 'SELECT * FROM users;'},
      );
      expect(userQueryResult.contains('error'), isTrue);

      final settingsQueryResult = await AiToolHandler.handleToolCall(
        'query_database',
        {'sql': 'SELECT * FROM app_settings;'},
      );
      expect(settingsQueryResult.contains('error'), isTrue);
    });

    test('get_table_schema blocks sensitive tables', () async {
      final userSchema = await AiToolHandler.handleToolCall(
        'get_table_schema',
        {'table_name': 'users'},
      );
      expect(userSchema.contains('error'), isTrue);
      expect(userSchema.contains('restricted'), isTrue);
    });
  });

  group('AI Harness: Conversation & Chat Models', () {
    test('AiConversationMessage and AiChatResult instantiate correctly', () {
      const msg = AiConversationMessage(
        role: 'user',
        content: 'สรุปสถานะเครื่องจักรที่มีใบแจ้งซ่อม',
      );
      expect(msg.role, equals('user'));
      expect(msg.content.contains('เครื่องจักร'), isTrue);

      const chatResult = AiChatResult(
        text: 'มีเครื่องจักรที่กำลังรอซ่อมทั้งหมด 2 เครื่อง',
        reasoningSteps: [
          'ค้นหาข้อมูลจากตาราง work_orders',
          'กรองสถานะ in_progress',
        ],
        reasoningContent: 'พบ WO-001 และ WO-002',
      );
      expect(chatResult.text.isNotEmpty, isTrue);
      expect(chatResult.reasoningSteps.length, equals(2));
      expect(chatResult.reasoningContent, isNotNull);
    });
  });
}
