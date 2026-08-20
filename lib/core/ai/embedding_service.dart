import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../database/db_helper.dart';
import 'ai_provider_config.dart';

final _log = Logger();

class EmbeddingService {
  static const _activeEmbeddingProviderKey = 'embedding_provider';
  static const _requestTimeout = Duration(seconds: 25);

  /// Load current embedding provider configuration from database settings.
  static Future<EmbeddingProviderConfig> loadConfig() async {
    try {
      final rows = await DbHelper.query(
        "SELECT setting_key, setting_value FROM app_settings "
        "WHERE setting_key LIKE 'embedding_%' OR setting_key LIKE 'ai_%' OR setting_key = 'gemini_api_key'",
      );

      final settings = <String, String>{};
      for (final row in rows) {
        final key = row['setting_key']?.toString();
        final value = row['setting_value']?.toString();
        if (key != null && value != null) {
          settings[key] = value;
        }
      }

      final providerId = settings[_activeEmbeddingProviderKey] ?? 'local';
      final kind = EmbeddingProviderCatalog.fromId(providerId);
      final definition = EmbeddingProviderCatalog.of(kind);

      final apiKey = settings['embedding_api_key_${definition.id}'] ??
          settings['ai_api_key_${definition.id}'] ??
          (kind == EmbeddingProviderKind.gemini ? settings['gemini_api_key'] ?? '' : '');

      final model = settings['embedding_model_${definition.id}'] ?? definition.defaultModel;
      final baseUrl = settings['embedding_base_url_${definition.id}'] ??
          settings['ai_base_url_${definition.id}'] ??
          definition.defaultBaseUrl;

      return EmbeddingProviderConfig(
        provider: kind,
        apiKey: apiKey.trim(),
        model: model.trim().isNotEmpty ? model.trim() : definition.defaultModel,
        baseUrl: baseUrl,
      );
    } catch (e) {
      _log.w('Failed to load embedding config, fallback to local: $e');
      return const EmbeddingProviderConfig(
        provider: EmbeddingProviderKind.local,
        apiKey: '',
        model: 'local-tfidf-ngram',
      );
    }
  }

  /// Save embedding provider configuration to database.
  static Future<void> saveConfig(EmbeddingProviderConfig config) async {
    final def = config.definition;
    await _writeSetting(_activeEmbeddingProviderKey, def.id);
    await _writeSetting('embedding_model_${def.id}', config.model);
    if (def.requiresApiKey || config.apiKey.isNotEmpty) {
      await _writeSetting('embedding_api_key_${def.id}', config.apiKey);
    }
    if (config.baseUrl != null && config.baseUrl!.trim().isNotEmpty) {
      await _writeSetting('embedding_base_url_${def.id}', config.baseUrl!.trim());
    }
  }

  static Future<void> _writeSetting(String key, String value) async {
    await DbHelper.execute('''
      INSERT INTO app_settings (setting_key, setting_value, updated_at)
      VALUES (@key, @val, CURRENT_TIMESTAMP)
      ON CONFLICT(setting_key) DO UPDATE SET
        setting_value = excluded.setting_value,
        updated_at = CURRENT_TIMESTAMP
    ''', params: {'key': key, 'val': value});
  }

  /// Generate embedding vector for a single text chunk.
  static Future<List<double>> getEmbedding(
    String text, {
    EmbeddingProviderConfig? overrideConfig,
  }) async {
    final results = await getBatchEmbeddings(
      [text],
      overrideConfig: overrideConfig,
    );
    return results.isNotEmpty ? results.first : [];
  }

  /// Generate embeddings for multiple texts.
  static Future<List<List<double>>> getBatchEmbeddings(
    List<String> texts, {
    EmbeddingProviderConfig? overrideConfig,
  }) async {
    final cleanTexts = texts.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    if (cleanTexts.isEmpty) return [];

    final config = overrideConfig ?? await loadConfig();

    try {
      switch (config.provider) {
        case EmbeddingProviderKind.mistral:
          return await _embedMistral(cleanTexts, config);
        case EmbeddingProviderKind.ollama:
          return await _embedOllama(cleanTexts, config);
        case EmbeddingProviderKind.gemini:
          return await _embedGemini(cleanTexts, config);
        case EmbeddingProviderKind.openai:
          return await _embedOpenAi(cleanTexts, config);
        case EmbeddingProviderKind.local:
          return cleanTexts.map(_embedLocal).toList();
      }
    } catch (e) {
      if (overrideConfig != null) {
        // Rethrow when testing from UI settings
        rethrow;
      }
      _log.e('Embedding provider (${config.provider.name}) failed: $e. Falling back to local.');
      return cleanTexts.map(_embedLocal).toList();
    }
  }

  /// Mistral AI Embedding API (POST /v1/embeddings)
  /// Docs: https://docs.mistral.ai/api/endpoint/embeddings
  static Future<List<List<double>>> _embedMistral(
    List<String> texts,
    EmbeddingProviderConfig config,
  ) async {
    final baseUrl = config.resolvedBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/embeddings');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.model.isNotEmpty ? config.model : 'mistral-embed',
            'input': texts,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = data['data'] as List<dynamic>? ?? [];
      return items.map((item) {
        final emb = (item['embedding'] as List<dynamic>?) ?? [];
        return emb.map((v) => (v as num).toDouble()).toList();
      }).toList();
    }

    throw HttpException('Mistral API error (${response.statusCode}): ${response.body}');
  }

  /// Ollama Embedding API (Supports local Host:Port and Ollama Cloud)
  static Future<List<List<double>>> _embedOllama(
    List<String> texts,
    EmbeddingProviderConfig config,
  ) async {
    final baseUrl = config.resolvedBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }

    // Try Ollama /api/embed (Batch endpoint supported in newer Ollama)
    try {
      final embedUri = Uri.parse('$baseUrl/api/embed');
      final response = await http
          .post(
            embedUri,
            headers: headers,
            body: jsonEncode({
              'model': config.model.isNotEmpty ? config.model : 'nomic-embed-text',
              'input': texts,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final embeddings = data['embeddings'] as List<dynamic>? ?? [];
        if (embeddings.isNotEmpty) {
          return embeddings.map((row) {
            return (row as List<dynamic>).map((v) => (v as num).toDouble()).toList();
          }).toList();
        }
      }
    } catch (_) {}

    // Fallback to sequential /api/embeddings for older Ollama versions
    final results = <List<double>>[];
    final legacyUri = Uri.parse('$baseUrl/api/embeddings');
    for (final text in texts) {
      final response = await http
          .post(
            legacyUri,
            headers: headers,
            body: jsonEncode({
              'model': config.model.isNotEmpty ? config.model : 'nomic-embed-text',
              'prompt': text,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final emb = (data['embedding'] as List<dynamic>?) ?? [];
        results.add(emb.map((v) => (v as num).toDouble()).toList());
      } else {
        throw HttpException('Ollama error (${response.statusCode}): ${response.body}');
      }
    }
    return results;
  }

  /// Google Gemini Embedding API (text-embedding-004)
  static Future<List<List<double>>> _embedGemini(
    List<String> texts,
    EmbeddingProviderConfig config,
  ) async {
    final modelName = config.model.isNotEmpty ? config.model : 'text-embedding-004';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:batchEmbedContents?key=${config.apiKey}',
    );

    final requests = texts.map((t) {
      return {
        'model': 'models/$modelName',
        'content': {
          'parts': [{'text': t}],
        },
      };
    }).toList();

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'requests': requests}),
        )
        .timeout(_requestTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final list = data['embeddings'] as List<dynamic>? ?? [];
      return list.map((item) {
        final values = (item['values'] as List<dynamic>?) ?? [];
        return values.map((v) => (v as num).toDouble()).toList();
      }).toList();
    }

    throw HttpException('Gemini API error (${response.statusCode}): ${response.body}');
  }

  /// OpenAI Embedding API (POST /v1/embeddings)
  static Future<List<List<double>>> _embedOpenAi(
    List<String> texts,
    EmbeddingProviderConfig config,
  ) async {
    final baseUrl = config.resolvedBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/embeddings');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.model.isNotEmpty ? config.model : 'text-embedding-3-small',
            'input': texts,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final items = data['data'] as List<dynamic>? ?? [];
      return items.map((item) {
        final emb = (item['embedding'] as List<dynamic>?) ?? [];
        return emb.map((v) => (v as num).toDouble()).toList();
      }).toList();
    }

    throw HttpException('OpenAI API error (${response.statusCode}): ${response.body}');
  }

  /// Zero-dependency deterministic N-Gram TF-IDF Vectorizer (256 dimensions)
  /// Ultra-fast, zero memory overhead, works 100% offline without external packages.
  static List<double> _embedLocal(String text) {
    const dim = 256;
    final vec = List<double>.filled(dim, 0.0);
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (normalized.isEmpty) return vec;

    final tokens = <String>[];
    final words = normalized.split(RegExp(r'[\s,._/\\:\-()]+'));
    tokens.addAll(words.where((w) => w.length >= 2));

    for (var i = 0; i < normalized.length - 2; i++) {
      tokens.add(normalized.substring(i, i + 3));
    }

    for (final token in tokens) {
      final hash = _hashString(token);
      final index = (hash.abs()) % dim;
      final sign = (hash >= 0) ? 1.0 : -1.0;
      vec[index] += sign * (1.0 + math.log(1.0 + token.length));
    }

    // L2 Normalize
    var sumSq = 0.0;
    for (var i = 0; i < dim; i++) {
      sumSq += vec[i] * vec[i];
    }
    if (sumSq > 0) {
      final norm = math.sqrt(sumSq);
      for (var i = 0; i < dim; i++) {
        vec[i] /= norm;
      }
    }

    return vec;
  }

  static int _hashString(String str) {
    var hash = 5381;
    for (var i = 0; i < str.length; i++) {
      hash = ((hash << 5) + hash) + str.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash;
  }
}
