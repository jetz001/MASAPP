enum AiProviderKind { gemini, openai, claude, deepseek, grok, mistral, ollama }

class AiProviderDefinition {
  final AiProviderKind kind;
  final String id;
  final String displayName;
  final String keyLabel;
  final String keyHint;
  final String helpText;
  final String defaultModel;
  final List<String> recommendedModels;
  final String? defaultBaseUrl;
  final bool requiresApiKey;
  final bool supportsCustomBaseUrl;

  const AiProviderDefinition({
    required this.kind,
    required this.id,
    required this.displayName,
    required this.keyLabel,
    required this.keyHint,
    required this.helpText,
    required this.defaultModel,
    required this.recommendedModels,
    this.defaultBaseUrl,
    this.requiresApiKey = true,
    this.supportsCustomBaseUrl = false,
  });
}

class AiProviderCatalog {
  static const providers = <AiProviderDefinition>[
    AiProviderDefinition(
      kind: AiProviderKind.gemini,
      id: 'gemini',
      displayName: 'Google Gemini',
      keyLabel: 'Gemini API Key',
      keyHint: 'AIzaSy...',
      helpText: 'รับ API Key ได้ที่ Google AI Studio (aistudio.google.com)',
      defaultModel: 'gemini-1.5-flash-latest',
      recommendedModels: ['gemini-1.5-flash-latest', 'gemini-1.5-pro-latest'],
    ),
    AiProviderDefinition(
      kind: AiProviderKind.openai,
      id: 'openai',
      displayName: 'OpenAI',
      keyLabel: 'OpenAI API Key',
      keyHint: 'sk-...',
      helpText: 'ใช้ API Key จาก OpenAI Platform',
      defaultModel: 'gpt-4o-mini',
      recommendedModels: ['gpt-4o-mini', 'gpt-4.1-mini', 'gpt-4o'],
      defaultBaseUrl: 'https://api.openai.com/v1',
    ),
    AiProviderDefinition(
      kind: AiProviderKind.claude,
      id: 'claude',
      displayName: 'Anthropic Claude',
      keyLabel: 'Claude API Key',
      keyHint: 'sk-ant-...',
      helpText: 'ใช้ API Key จาก Anthropic Console',
      defaultModel: 'claude-3-5-haiku-latest',
      recommendedModels: [
        'claude-3-5-haiku-latest',
        'claude-3-5-sonnet-latest',
      ],
      defaultBaseUrl: 'https://api.anthropic.com/v1',
    ),
    AiProviderDefinition(
      kind: AiProviderKind.deepseek,
      id: 'deepseek',
      displayName: 'DeepSeek',
      keyLabel: 'DeepSeek API Key',
      keyHint: 'sk-...',
      helpText: 'ใช้ API Key จาก DeepSeek Platform',
      defaultModel: 'deepseek-chat',
      recommendedModels: ['deepseek-chat', 'deepseek-reasoner'],
      defaultBaseUrl: 'https://api.deepseek.com',
    ),
    AiProviderDefinition(
      kind: AiProviderKind.grok,
      id: 'grok',
      displayName: 'xAI Grok',
      keyLabel: 'Grok API Key',
      keyHint: 'xai-...',
      helpText: 'ใช้ API Key จาก xAI Console',
      defaultModel: 'grok-beta',
      recommendedModels: ['grok-beta', 'grok-2-1212'],
      defaultBaseUrl: 'https://api.x.ai/v1',
    ),
    AiProviderDefinition(
      kind: AiProviderKind.mistral,
      id: 'mistral',
      displayName: 'Mistral',
      keyLabel: 'Mistral API Key',
      keyHint: 'mst-...',
      helpText: 'ใช้ API Key จาก Mistral Console',
      defaultModel: 'mistral-small-latest',
      recommendedModels: ['mistral-small-latest', 'mistral-large-latest'],
      defaultBaseUrl: 'https://api.mistral.ai/v1',
    ),
    AiProviderDefinition(
      kind: AiProviderKind.ollama,
      id: 'ollama',
      displayName: 'Ollama',
      keyLabel: 'Ollama API Key',
      keyHint: 'ปล่อยว่างได้ถ้าไม่ได้ตั้ง auth',
      helpText: 'เชื่อมต่อ Ollama ในเครื่องหรือในเครือข่ายภายใน',
      defaultModel: 'llama3.1:8b',
      recommendedModels: ['llama3.1:8b', 'qwen2.5:7b', 'mistral:7b'],
      defaultBaseUrl: 'http://127.0.0.1:11434',
      requiresApiKey: false,
      supportsCustomBaseUrl: true,
    ),
  ];

  static AiProviderDefinition of(AiProviderKind kind) {
    return providers.firstWhere((provider) => provider.kind == kind);
  }

  static AiProviderKind fromId(String? id) {
    final normalized = id?.trim().toLowerCase();
    for (final provider in providers) {
      if (provider.id == normalized) return provider.kind;
    }
    return AiProviderKind.gemini;
  }
}

class AiProviderConfig {
  final AiProviderKind provider;
  final String apiKey;
  final String model;
  final String? baseUrl;

  const AiProviderConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
  });

  AiProviderDefinition get definition => AiProviderCatalog.of(provider);

  bool get isComplete {
    final hasBaseUrl =
        !definition.supportsCustomBaseUrl ||
        ((baseUrl ?? '').trim().isNotEmpty);
    final hasApiKey = !definition.requiresApiKey || apiKey.trim().isNotEmpty;
    return hasBaseUrl && hasApiKey && model.trim().isNotEmpty;
  }

  String get resolvedBaseUrl =>
      (baseUrl ?? definition.defaultBaseUrl ?? '').trim();

  AiProviderConfig copyWith({
    AiProviderKind? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
  }) {
    return AiProviderConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}
