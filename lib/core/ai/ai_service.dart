import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../database/db_helper.dart';
import 'ai_provider_config.dart';
import 'ai_tool_handler.dart';

class AiConversationMessage {
  final String role;
  final String content;

  const AiConversationMessage({required this.role, required this.content});
}

class AiService {
  static const _activeProviderKey = 'ai_provider';
  static const _legacyGeminiKey = 'gemini_api_key';
  static const _requestTimeout = Duration(seconds: 30);

  static const _systemInstruction = '''
You are MASAPP AI Assistant, an intelligent assistant for a factory maintenance management system.

IMPORTANT CONSTRAINTS:
1. You can ONLY access data from the MASAPP database. Never use external knowledge about specific company data.
2. Always use query_database or get_available_tables tools when you need data.
3. Only answer questions related to maintenance, machines, work orders, spare parts, tools, PM/AM, OEE, and factory operations.
4. ALWAYS respond in Thai language unless the user writes in another language.
5. Be concise and structured. Use bullet points or tables when presenting data.
6. If no data is found, say so clearly. Never make up numbers or statuses.
7. You may freely explore any non-sensitive table in the MASAPP database to understand the data before answering.
8. When user wording is ambiguous, try related business terms and synonyms found in the database instead of failing too early.
9. Prefer this workflow: inspect available tables -> inspect schema -> run focused queries -> summarize findings.
10. When presenting structured results, prefer markdown tables, unless the user asks for a timeline or the data is clearly chronological.
11. When the user may want to copy text, SQL, lists, or templates, wrap that part in fenced code blocks using ```text or ```sql.
12. When you want to show an image, use markdown image syntax exactly like ![caption](image_url_or_file_path). Do not use normal markdown links for images.
13. When the user asks for machine manuals, machine files, machine photos, PDFs, attachments, or document evidence for a machine, use find_machine_assets before saying that nothing exists.
14. When you need external information, use external search only after checking the MASAPP database first or when the user explicitly asks for outside information.
15. When using external information, clearly label it with the heading "ข้อมูลภายนอก" and state the provider/source. Do not mix it silently with MASAPP database facts.
16. For Thai/local requests, prefer Thai sources first when using external search.
17. When the user asks for a timeline, event history, repair sequence, or chronological trace, use a fenced block with language timeline and a JSON array.
18. Each timeline item should use keys: time, title, detail, type. Use type values such as created, in_progress, update, completed, warning, or critical.
19. Sort timeline items from oldest to newest unless the user asks otherwise.
20. When you want to show a PDF/file card, use a fenced block with language pdfcard and a JSON object with keys: title, path, pages, thumbnail. Set thumbnail only when it is an actual image URL/path, not a PDF URL.
21. File metadata is available in file_assets, including storage_path, thumbnail_path, preview_path, mime_type, page_count, module_type, entity_id, and display_name.

Available data in this system:
- Machines (เครื่องจักร): status, specs, location, running hours
- Work Orders (ใบแจ้งซ่อม): status, priority, assigned technician, RCA
- PM/AM Plans (แผนการบำรุงรักษา): schedules, tasks, executions
- Spare Parts (อะไหล่): inventory, transactions, reorder levels
- Tools (เครื่องมือช่าง): checkout status, location
- Work Permits (ใบอนุญาตทำงาน): status, safety checks
- File Assets (ไฟล์แนบ/รูป/PDF): normalized file paths, previews, thumbnails, page counts
- OEE Logs, Factory Layout, Technician skills, notifications, handover/checklist data

Start by greeting the user and asking how you can help with maintenance operations today.
''';

  static final _queryDbTool = FunctionDeclaration(
    'query_database',
    'Execute a SQLite SELECT query on the MASAPP database to retrieve '
        'operational data. Only SELECT statements allowed. Results capped at 200 rows.',
    Schema(
      SchemaType.object,
      properties: {
        'sql': Schema(
          SchemaType.string,
          description:
              'A valid SQLite SELECT statement. Must start with SELECT.',
        ),
        'description': Schema(
          SchemaType.string,
          description: 'Brief description of what this query is for.',
        ),
      },
      requiredProperties: ['sql'],
    ),
  );

  static final _getTablesTool = FunctionDeclaration(
    'get_available_tables',
    'Get a list of all database tables the AI can query, with their column names.',
    Schema(SchemaType.object, properties: {}),
  );

  static final _getSchemaTool = FunctionDeclaration(
    'get_table_schema',
    'Get column names and data types for a specific table.',
    Schema(
      SchemaType.object,
      properties: {
        'table_name': Schema(
          SchemaType.string,
          description: 'The table name to inspect.',
        ),
      },
      requiredProperties: ['table_name'],
    ),
  );

  static final _externalWebSearchTool = FunctionDeclaration(
    'search_external_web',
    'Search external sources only after checking the MASAPP database first or when the user explicitly asks for external information. Returns clearly labeled external data.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(
          SchemaType.string,
          description: 'Search query for external web lookup.',
        ),
        'db_context': Schema(
          SchemaType.string,
          description:
              'Short summary of what was checked in the MASAPP database first.',
        ),
        'why_external_needed': Schema(
          SchemaType.string,
          description:
              'Why external search is necessary after checking the database.',
        ),
        'max_results': Schema(
          SchemaType.integer,
          description: 'Maximum number of results to return.',
        ),
      },
      requiredProperties: ['query', 'db_context', 'why_external_needed'],
    ),
  );

  static final _findMachineAssetsTool = FunctionDeclaration(
    'find_machine_assets',
    'Find manuals, PDFs, attachments, and images related to a machine by machine number, name, asset number, brand, model, or serial number.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(
          SchemaType.string,
          description:
              'Machine identifier or search text, such as machine number, name, brand, model, or serial number.',
        ),
        'asset_type': Schema(
          SchemaType.string,
          description: 'Optional filter: all, document, pdf, or image.',
        ),
      },
      requiredProperties: ['query'],
    ),
  );

  static final _externalImageSearchTool = FunctionDeclaration(
    'search_external_images',
    'Search external image sources only after checking the MASAPP database first or when the user explicitly asks for outside images. Returns clearly labeled external image data.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(SchemaType.string, description: 'Image search query.'),
        'db_context': Schema(
          SchemaType.string,
          description:
              'Short summary of what was checked in the MASAPP database first.',
        ),
        'why_external_needed': Schema(
          SchemaType.string,
          description:
              'Why external image search is necessary after checking the database.',
        ),
        'max_results': Schema(
          SchemaType.integer,
          description: 'Maximum number of images to return.',
        ),
      },
      requiredProperties: ['query', 'db_context', 'why_external_needed'],
    ),
  );

  static final _openAiTools = [
    {
      'type': 'function',
      'function': {
        'name': 'query_database',
        'description':
            'Execute a SQLite SELECT query on the MASAPP database to retrieve operational data. Only SELECT statements allowed. Results capped at 200 rows.',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {
              'type': 'string',
              'description':
                  'A valid SQLite SELECT statement. Must start with SELECT.',
            },
            'description': {
              'type': 'string',
              'description': 'Brief description of what this query is for.',
            },
          },
          'required': ['sql'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_available_tables',
        'description':
            'Get a list of all database tables the AI can query, with their column names.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_table_schema',
        'description': 'Get column names and data types for a specific table.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table_name': {
              'type': 'string',
              'description': 'The table name to inspect.',
            },
          },
          'required': ['table_name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'find_machine_assets',
        'description':
            'Find manuals, PDFs, attachments, and images related to a machine by machine number, name, asset number, brand, model, or serial number.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'Machine identifier or search text, such as machine number, name, brand, model, or serial number.',
            },
            'asset_type': {
              'type': 'string',
              'description': 'Optional filter: all, document, pdf, or image.',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_external_web',
        'description':
            'Search external sources only after checking the MASAPP database first or when the user explicitly asks for external information. Returns clearly labeled external data.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search query for external web lookup.',
            },
            'db_context': {
              'type': 'string',
              'description':
                  'Short summary of what was checked in the MASAPP database first.',
            },
            'why_external_needed': {
              'type': 'string',
              'description':
                  'Why external search is necessary after checking the database.',
            },
            'max_results': {
              'type': 'integer',
              'description': 'Maximum number of results to return.',
            },
          },
          'required': ['query', 'db_context', 'why_external_needed'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_external_images',
        'description':
            'Search external image sources only after checking the MASAPP database first or when the user explicitly asks for outside images. Returns clearly labeled external image data.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Image search query.'},
            'db_context': {
              'type': 'string',
              'description':
                  'Short summary of what was checked in the MASAPP database first.',
            },
            'why_external_needed': {
              'type': 'string',
              'description':
                  'Why external image search is necessary after checking the database.',
            },
            'max_results': {
              'type': 'integer',
              'description': 'Maximum number of images to return.',
            },
          },
          'required': ['query', 'db_context', 'why_external_needed'],
        },
      },
    },
  ];

  static final _anthropicTools = [
    {
      'name': 'query_database',
      'description':
          'Execute a SQLite SELECT query on the MASAPP database to retrieve operational data. Only SELECT statements allowed. Results capped at 200 rows.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'sql': {
            'type': 'string',
            'description':
                'A valid SQLite SELECT statement. Must start with SELECT.',
          },
          'description': {
            'type': 'string',
            'description': 'Brief description of what this query is for.',
          },
        },
        'required': ['sql'],
      },
    },
    {
      'name': 'get_available_tables',
      'description':
          'Get a list of all database tables the AI can query, with their column names.',
      'input_schema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'get_table_schema',
      'description': 'Get column names and data types for a specific table.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'table_name': {
            'type': 'string',
            'description': 'The table name to inspect.',
          },
        },
        'required': ['table_name'],
      },
    },
    {
      'name': 'find_machine_assets',
      'description':
          'Find manuals, PDFs, attachments, and images related to a machine by machine number, name, asset number, brand, model, or serial number.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Machine identifier or search text, such as machine number, name, brand, model, or serial number.',
          },
          'asset_type': {
            'type': 'string',
            'description': 'Optional filter: all, document, pdf, or image.',
          },
        },
        'required': ['query'],
      },
    },
    {
      'name': 'search_external_web',
      'description':
          'Search external sources only after checking the MASAPP database first or when the user explicitly asks for external information. Returns clearly labeled external data.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query for external web lookup.',
          },
          'db_context': {
            'type': 'string',
            'description':
                'Short summary of what was checked in the MASAPP database first.',
          },
          'why_external_needed': {
            'type': 'string',
            'description':
                'Why external search is necessary after checking the database.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of results to return.',
          },
        },
        'required': ['query', 'db_context', 'why_external_needed'],
      },
    },
    {
      'name': 'search_external_images',
      'description':
          'Search external image sources only after checking the MASAPP database first or when the user explicitly asks for outside images. Returns clearly labeled external image data.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Image search query.'},
          'db_context': {
            'type': 'string',
            'description':
                'Short summary of what was checked in the MASAPP database first.',
          },
          'why_external_needed': {
            'type': 'string',
            'description':
                'Why external image search is necessary after checking the database.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of images to return.',
          },
        },
        'required': ['query', 'db_context', 'why_external_needed'],
      },
    },
  ];

  static Future<AiProviderConfig> loadConfig() async {
    final provider = AiProviderCatalog.fromId(
      await _getSetting(_activeProviderKey),
    );
    return loadConfigForProvider(provider);
  }

  static Future<AiProviderConfig> loadConfigForProvider(
    AiProviderKind provider,
  ) async {
    final definition = AiProviderCatalog.of(provider);
    final apiKey = await _getApiKey(provider) ?? '';
    final model =
        await _getSetting(_modelSettingKey(provider)) ??
        definition.defaultModel;
    final baseUrl = definition.supportsCustomBaseUrl
        ? (await _getSetting(_baseUrlSettingKey(provider))) ??
              definition.defaultBaseUrl
        : definition.defaultBaseUrl;

    return AiProviderConfig(
      provider: provider,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl,
    );
  }

  static Future<void> saveConfig(AiProviderConfig config) async {
    await _saveSetting(
      _activeProviderKey,
      config.definition.id,
      description: 'Active AI provider',
    );
    await _saveSetting(
      _modelSettingKey(config.provider),
      config.model.trim(),
      description: '${config.definition.displayName} model',
    );
    if (config.definition.supportsCustomBaseUrl) {
      await _saveSetting(
        _baseUrlSettingKey(config.provider),
        config.resolvedBaseUrl,
        description: '${config.definition.displayName} base URL',
      );
    }
    if (config.definition.requiresApiKey || config.apiKey.trim().isNotEmpty) {
      await _saveSetting(
        _apiKeySettingKey(config.provider),
        config.apiKey.trim(),
        description: '${config.definition.displayName} API key',
      );
      if (config.provider == AiProviderKind.gemini) {
        await _saveSetting(
          _legacyGeminiKey,
          config.apiKey.trim(),
          description: 'Legacy Gemini API key',
        );
      }
    }
  }

  static Future<void> saveApiKey(String key) async {
    final current = await loadConfig();
    await saveConfig(current.copyWith(apiKey: key));
  }

  static Future<bool> isConfigured() async {
    final config = await loadConfig();
    return config.isComplete;
  }

  static Future<bool> testApiKey(String key) async {
    final current = await loadConfig();
    return testConfig(current.copyWith(apiKey: key));
  }

  static Future<bool> testConfig(AiProviderConfig config) async {
    if (!config.isComplete) return false;

    try {
      await _ensureProviderReachable(config);
      switch (config.provider) {
        case AiProviderKind.gemini:
          return await _testGemini(config);
        case AiProviderKind.claude:
          return await _testClaude(config);
        case AiProviderKind.ollama:
          return await _testOllama(config);
        case AiProviderKind.openai:
        case AiProviderKind.deepseek:
        case AiProviderKind.grok:
        case AiProviderKind.mistral:
          return await _testOpenAiCompatible(config);
      }
    } catch (_) {
      return false;
    }
  }

  static Future<String> chat({
    required AiProviderConfig config,
    required List<AiConversationMessage> history,
    required String userMessage,
  }) async {
    await _ensureProviderReachable(config);

    switch (config.provider) {
      case AiProviderKind.gemini:
        return _chatWithGemini(config, history, userMessage);
      case AiProviderKind.claude:
        return _chatWithClaude(config, history, userMessage);
      case AiProviderKind.ollama:
        return _chatWithOllama(config, history, userMessage);
      case AiProviderKind.openai:
      case AiProviderKind.deepseek:
      case AiProviderKind.grok:
      case AiProviderKind.mistral:
        return _chatWithOpenAiCompatible(config, history, userMessage);
    }
  }

  static Future<String> _chatWithGemini(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final model = GenerativeModel(
      model: config.model,
      apiKey: config.apiKey,
      systemInstruction: Content.system(_systemInstruction),
      tools: [
        Tool(
          functionDeclarations: [
            _queryDbTool,
            _getTablesTool,
            _getSchemaTool,
            _findMachineAssetsTool,
            _externalWebSearchTool,
            _externalImageSearchTool,
          ],
        ),
      ],
      generationConfig: GenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 2048,
      ),
    );

    final geminiHistory = history.map((message) {
      if (message.role == 'assistant') {
        return Content.model([TextPart(message.content)]);
      }
      return Content.text(message.content);
    }).toList();

    final session = model.startChat(history: geminiHistory);
    var response = await session.sendMessage(Content.text(userMessage));

    for (var i = 0; i < 8 && response.functionCalls.isNotEmpty; i++) {
      final functionResponses = <FunctionResponse>[];

      for (final call in response.functionCalls) {
        final result = await AiToolHandler.handleToolCall(
          call.name,
          call.args.cast<String, dynamic>(),
        );
        functionResponses.add(FunctionResponse(call.name, {'output': result}));
      }

      response = await session.sendMessage(
        Content.functionResponses(functionResponses),
      );
    }

    return response.text ?? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<String> _chatWithOpenAiCompatible(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemInstruction},
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    for (var i = 0; i < 8; i++) {
      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/chat/completions'),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        body: {
          'model': config.model,
          'messages': messages,
          'tools': _openAiTools,
          'tool_choice': 'auto',
          'temperature': 0.3,
          'max_tokens': 2048,
        },
      );

      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) {
        throw Exception('No choices returned from AI provider');
      }

      final choice = choices.first as Map<String, dynamic>;
      final message =
          (choice['message'] as Map?)?.cast<String, dynamic>() ?? {};
      final toolCalls = (message['tool_calls'] as List?) ?? const [];

      if (toolCalls.isEmpty) {
        final text = _extractOpenAiContent(message['content']);
        return text.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : text;
      }

      messages.add({
        'role': 'assistant',
        'content': message['content'],
        'tool_calls': toolCalls,
      });

      for (final rawCall in toolCalls.cast<Map<String, dynamic>>()) {
        final function =
            (rawCall['function'] as Map?)?.cast<String, dynamic>() ?? {};
        final args = _decodeArguments(function['arguments']);
        final result = await AiToolHandler.handleToolCall(
          function['name']?.toString() ?? '',
          args,
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': rawCall['id'],
          'content': result,
        });
      }
    }

    return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<String> _chatWithClaude(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final messages = <Map<String, dynamic>>[
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    for (var i = 0; i < 8; i++) {
      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/messages'),
        headers: {
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: {
          'model': config.model,
          'system': _systemInstruction,
          'messages': messages,
          'tools': _anthropicTools,
          'temperature': 0.3,
          'max_tokens': 2048,
        },
      );

      final content = (json['content'] as List?) ?? const [];
      final textParts = <String>[];
      final toolResults = <Map<String, dynamic>>[];

      for (final block in content.cast<Map<String, dynamic>>()) {
        final type = block['type']?.toString() ?? '';
        if (type == 'text') {
          final text = block['text']?.toString() ?? '';
          if (text.isNotEmpty) textParts.add(text);
          continue;
        }
        if (type == 'tool_use') {
          final result = await AiToolHandler.handleToolCall(
            block['name']?.toString() ?? '',
            (block['input'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{},
          );
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': block['id'],
            'content': result,
          });
        }
      }

      if (toolResults.isEmpty) {
        final text = textParts.join('\n').trim();
        return text.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : text;
      }

      messages.add({'role': 'assistant', 'content': content});
      messages.add({'role': 'user', 'content': toolResults});
    }

    return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<String> _chatWithOllama(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemInstruction},
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    for (var i = 0; i < 8; i++) {
      final headers = <String, String>{};
      if (config.apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }

      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/api/chat'),
        headers: headers,
        body: {
          'model': config.model,
          'messages': messages,
          'stream': false,
          'tools': _openAiTools,
        },
      );

      final message = (json['message'] as Map?)?.cast<String, dynamic>() ?? {};
      final toolCalls = (message['tool_calls'] as List?) ?? const [];

      if (toolCalls.isEmpty) {
        final text = message['content']?.toString().trim() ?? '';
        return text.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : text;
      }

      messages.add({
        'role': 'assistant',
        'content': message['content'],
        'tool_calls': toolCalls,
      });

      for (final rawCall in toolCalls.cast<Map<String, dynamic>>()) {
        final function =
            (rawCall['function'] as Map?)?.cast<String, dynamic>() ?? {};
        final args = _decodeArguments(function['arguments']);
        final result = await AiToolHandler.handleToolCall(
          function['name']?.toString() ?? '',
          args,
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': rawCall['id'],
          'content': result,
        });
      }
    }

    return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<bool> _testGemini(AiProviderConfig config) async {
    final model = GenerativeModel(
      model: config.model,
      apiKey: config.apiKey,
      generationConfig: GenerationConfig(maxOutputTokens: 10),
    );
    await model.generateContent([Content.text('ping')]);
    return true;
  }

  static Future<bool> _testOpenAiCompatible(AiProviderConfig config) async {
    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/chat/completions'),
      headers: {'Authorization': 'Bearer ${config.apiKey}'},
      body: {
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 8,
      },
    );
    return true;
  }

  static Future<bool> _testClaude(AiProviderConfig config) async {
    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/messages'),
      headers: {'x-api-key': config.apiKey, 'anthropic-version': '2023-06-01'},
      body: {
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 8,
      },
    );
    return true;
  }

  static Future<bool> _testOllama(AiProviderConfig config) async {
    final headers = <String, String>{};
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/api/chat'),
      headers: headers,
      body: {
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'stream': false,
      },
    );
    return true;
  }

  static Future<Map<String, dynamic>> _postJson(
    String url, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json', ...headers},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Invalid response format');
  }

  static String _normalizeBaseUrl(String baseUrl, String suffix) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return '$trimmed$suffix';
  }

  static String _extractOpenAiContent(dynamic content) {
    if (content == null) return '';
    if (content is String) return content.trim();
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .join('\n')
          .trim();
    }
    return content.toString().trim();
  }

  static Map<String, dynamic> _decodeArguments(dynamic rawArguments) {
    if (rawArguments is Map<String, dynamic>) return rawArguments;
    if (rawArguments is Map) return rawArguments.cast<String, dynamic>();
    if (rawArguments is String && rawArguments.trim().isNotEmpty) {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  static String _extractError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          return error['message']?.toString() ?? 'HTTP $statusCode';
        }
        if (error != null) return error.toString();
      }
    } catch (_) {}
    return 'HTTP $statusCode';
  }

  static Future<void> _ensureProviderReachable(AiProviderConfig config) async {
    final isCloudProvider = config.provider != AiProviderKind.ollama;
    final baseUrl = config.resolvedBaseUrl;

    if (baseUrl.isEmpty) {
      throw Exception('ยังไม่ได้ตั้งค่า Base URL ของ AI Provider');
    }

    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host ?? '';
    if (host.isEmpty) {
      throw Exception('Base URL ของ AI Provider ไม่ถูกต้อง');
    }

    try {
      final results = await InternetAddress.lookup(host);
      if (results.isEmpty) {
        throw const SocketException('No address resolved');
      }
    } on SocketException {
      if (isCloudProvider) {
        throw Exception(
          'ไม่มีการเชื่อมต่ออินเทอร์เน็ต หรือไม่สามารถเข้าถึง ${config.definition.displayName} ได้ในขณะนี้',
        );
      }
      throw Exception(
        'ไม่สามารถเชื่อมต่อ ${config.definition.displayName} ได้ กรุณาตรวจสอบว่า service กำลังรันอยู่',
      );
    }
  }

  static String _apiKeySettingKey(AiProviderKind provider) {
    return 'ai_api_key_${AiProviderCatalog.of(provider).id}';
  }

  static String _modelSettingKey(AiProviderKind provider) {
    return 'ai_model_${AiProviderCatalog.of(provider).id}';
  }

  static String _baseUrlSettingKey(AiProviderKind provider) {
    return 'ai_base_url_${AiProviderCatalog.of(provider).id}';
  }

  static Future<String?> _getApiKey(AiProviderKind provider) async {
    final key = await _getSetting(_apiKeySettingKey(provider));
    if ((key ?? '').isNotEmpty) return key;
    if (provider == AiProviderKind.gemini) {
      return _getSetting(_legacyGeminiKey);
    }
    return null;
  }

  static Future<String?> _getSetting(String key) async {
    try {
      final row = await DbHelper.queryOne(
        'SELECT setting_value FROM app_settings WHERE setting_key = @key',
        params: {'key': key},
      );
      return row?['setting_value']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveSetting(
    String key,
    String value, {
    String? description,
  }) async {
    await DbHelper.execute(
      '''INSERT INTO app_settings(setting_key, setting_value, description, updated_at)
         VALUES(@key, @value, @description, CURRENT_TIMESTAMP)
         ON CONFLICT(setting_key)
         DO UPDATE SET
           setting_value = excluded.setting_value,
           description = excluded.description,
           updated_at = excluded.updated_at''',
      params: {'key': key, 'value': value, 'description': description ?? ''},
    );
  }
}
