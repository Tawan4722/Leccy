import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<GeneratedSlide>> generateSlides({
    required String apiKey,
    required String title,
    required String noteText,
    String provider = 'gemini',
    String baseUrl = '',
    String model = '',
    String? preset,
    String? customBaseUrl,
    String? customModel,
  }) async {
    final json = await _generateJson(
      apiKey: apiKey,
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      legacyPreset: preset,
      legacyCustomBaseUrl: customBaseUrl,
      legacyCustomModel: customModel,
      prompt:
          'Create a concise lecture presentation as JSON with key "slides". '
          'Each slide must have "title", "bullets" as an array of strings, '
          'and optional "notes". Use 4 to 8 slides.\n\n'
          'Lecture title: $title\n\nNotes:\n$noteText',
    );
    final slides = json['slides'];
    if (slides is! List) {
      throw const GeminiException('AI did not return slides.');
    }
    return slides
        .whereType<Map>()
        .map((item) => GeneratedSlide.fromJson(item.cast<String, Object?>()))
        .where((slide) => slide.title.trim().isNotEmpty)
        .toList();
  }

  Future<List<GeneratedFlashcard>> generateFlashcards({
    required String apiKey,
    required String title,
    required String noteText,
    String provider = 'gemini',
    String baseUrl = '',
    String model = '',
    String? preset,
    String? customBaseUrl,
    String? customModel,
  }) async {
    final json = await _generateJson(
      apiKey: apiKey,
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      legacyPreset: preset,
      legacyCustomBaseUrl: customBaseUrl,
      legacyCustomModel: customModel,
      prompt:
          'Create study flashcards as JSON with key "cards". Each card must '
          'have "question", "answer", and "topic". Use 8 to 16 cards.\n\n'
          'Lecture title: $title\n\nNotes:\n$noteText',
    );
    final cards = json['cards'];
    if (cards is! List) {
      throw const GeminiException('AI did not return flashcards.');
    }
    return cards
        .whereType<Map>()
        .map(
          (item) => GeneratedFlashcard.fromJson(item.cast<String, Object?>()),
        )
        .where((card) => card.question.trim().isNotEmpty)
        .toList();
  }

  Future<StructuredNote> restructureNote({
    required String apiKey,
    required String title,
    required String noteText,
    String provider = 'gemini',
    String baseUrl = '',
    String model = '',
    String? preset,
    String? customBaseUrl,
    String? customModel,
  }) async {
    final json = await _generateJson(
      apiKey: apiKey,
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      legacyPreset: preset,
      legacyCustomBaseUrl: customBaseUrl,
      legacyCustomModel: customModel,
      prompt:
          'Restructure this lecture note into a clean hierarchy as JSON. '
          'Return exactly these keys: "title" and "sections". "sections" must '
          'be an array where each section has "heading", optional "body", and '
          'optional "subsections". Each subsection has "heading" and optional '
          '"body". Keep all important facts. Do not invent facts.\n\n'
          'Current title: $title\n\nOriginal notes:\n$noteText',
    );
    return StructuredNote.fromJson(json);
  }

  Future<Map<String, Object?>> _generateJson({
    required String apiKey,
    required String prompt,
    required String provider,
    required String baseUrl,
    required String model,
    required String? legacyPreset,
    required String? legacyCustomBaseUrl,
    required String? legacyCustomModel,
  }) async {
    final resolvedProvider = _normalizeProvider(
      legacyPreset != null ? legacyPreset : provider,
    );
    final resolvedBaseUrl = baseUrl.trim().isNotEmpty
        ? baseUrl.trim()
        : (legacyCustomBaseUrl ?? '').trim();
    final resolvedCustomModel = model.trim().isNotEmpty
        ? model.trim()
        : (legacyCustomModel ?? '').trim();
    final cleanKey = apiKey.trim();

    String selectedModel = resolvedCustomModel;
    if (selectedModel.isEmpty) {
      selectedModel = _defaultModelForProvider(resolvedProvider);
    }

    final uri = _resolveEndpoint(
      provider: resolvedProvider,
      model: selectedModel,
      customBaseUrl: resolvedBaseUrl,
    );

    final Map<String, String> headers = {'Content-Type': 'application/json'};
    if (resolvedProvider == 'gemini') {
      if (cleanKey.isEmpty) {
        throw const GeminiException('Please enter your Gemini API key in Settings first.');
      }
      headers['x-goog-api-key'] = cleanKey;
    } else if (resolvedProvider == 'anthropic') {
      if (cleanKey.isEmpty) {
        throw const GeminiException('Please enter your Anthropic API key in Settings first.');
      }
      headers['x-api-key'] = cleanKey;
      headers['anthropic-version'] = '2023-06-01';
    } else {
      if (cleanKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $cleanKey';
      } else if (resolvedProvider == 'openai') {
        throw const GeminiException('Please enter your OpenAI API key in Settings first.');
      } else if (resolvedProvider == 'deepseek') {
        throw const GeminiException('Please enter your DeepSeek API key in Settings first.');
      }
    }

    late http.Response response;
    if (resolvedProvider == 'gemini') {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
          },
        }),
      );
    } else if (resolvedProvider == 'anthropic') {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'model': selectedModel,
          'max_tokens': 4000,
          'system':
              'Return only a single JSON object. No markdown and no prose.',
          'messages': [
            {
              'role': 'user',
              'content': '$prompt\n\nRespond ONLY with raw JSON. Do not include markdown blocks or conversational text.',
            },
          ],
        }),
      );
    } else {
      final Map<String, dynamic> body = {
        'model': selectedModel,
        'messages': [
          {
            'role': 'system',
            'content': 'You are a helpful assistant. You must respond ONLY with a single valid JSON object. Do not wrap it in markdown code blocks or add text before/after.'
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
      };

      if (resolvedProvider == 'openai' || resolvedProvider == 'deepseek') {
        body['response_format'] = {'type': 'json_object'};
      }

      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiException('AI request failed: Status ${response.statusCode}\nDetail: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    String? textResponse;

    if (resolvedProvider == 'gemini') {
      final candidates = decoded is Map ? decoded['candidates'] : null;
      final content = candidates is List && candidates.isNotEmpty
          ? candidates.first['content']
          : null;
      final parts = content is Map ? content['parts'] : null;
      textResponse = parts is List && parts.isNotEmpty ? parts.first['text'] : null;
    } else if (resolvedProvider == 'anthropic') {
      final content = decoded is Map ? decoded['content'] : null;
      if (content is List && content.isNotEmpty) {
        final first = content.first;
        if (first is Map) {
          textResponse = first['text']?.toString();
        } else {
          textResponse = first.toString();
        }
      }
    } else {
      final choices = decoded is Map ? decoded['choices'] : null;
      final firstChoice = choices is List && choices.isNotEmpty ? choices.first : null;
      final message = firstChoice is Map ? firstChoice['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String) {
        textResponse = content;
      } else if (content is List) {
        final parts = content
            .whereType<Map>()
            .map((part) => part['text']?.toString() ?? '')
            .where((part) => part.trim().isNotEmpty)
            .toList();
        textResponse = parts.isEmpty ? null : parts.join('\n');
      }
    }

    if (textResponse == null || textResponse.trim().isEmpty) {
      throw const GeminiException('AI returned an empty response.');
    }

    final cleanedJson = _cleanJsonResponse(textResponse);
    final parsed = jsonDecode(cleanedJson);
    if (parsed is! Map) {
      throw const GeminiException('AI did not return a valid JSON structure.');
    }
    return parsed.cast<String, Object?>();
  }

  String _cleanJsonResponse(String rawResponse) {
    var cleaned = rawResponse.trim();

    if (cleaned.contains('```')) {
      final lines = cleaned.split('\n');
      if (lines.first.startsWith('```')) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.last.startsWith('```')) {
        lines.removeLast();
      }
      cleaned = lines.join('\n').trim();
    }

    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }

    return cleaned;
  }

  String _normalizeProvider(String value) {
    switch (value.trim().toLowerCase()) {
      case 'openai':
      case 'anthropic':
      case 'deepseek':
      case 'gemini':
        return value.trim().toLowerCase();
      case 'ollama':
      case 'custom':
      case 'ollama_custom':
        return 'ollama_custom';
      default:
        return 'gemini';
    }
  }

  String _defaultModelForProvider(String provider) {
    switch (provider) {
      case 'openai':
        return 'gpt-4o-mini';
      case 'anthropic':
        return 'claude-3-5-sonnet-20241022';
      case 'deepseek':
        return 'deepseek-chat';
      case 'ollama_custom':
        return 'llama3.1';
      case 'gemini':
      default:
        return 'gemini-2.5-flash';
    }
  }

  Uri _resolveEndpoint({
    required String provider,
    required String model,
    required String customBaseUrl,
  }) {
    if (provider == 'gemini') {
      final base = customBaseUrl.trim();
      if (base.isEmpty) {
        return Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
        );
      }
      if (base.contains('{model}')) {
        return Uri.parse(base.replaceAll('{model}', model));
      }
      if (base.contains(':generateContent')) {
        return Uri.parse(base);
      }
      final separator = base.endsWith('/') ? '' : '/';
      return Uri.parse('${base}${separator}models/$model:generateContent');
    }

    if (provider == 'anthropic') {
      var resolved = customBaseUrl.trim();
      if (resolved.isEmpty) {
        resolved = 'https://api.anthropic.com/v1/messages';
      } else if (!resolved.endsWith('/messages') &&
          !resolved.contains('/messages?')) {
        if (resolved.endsWith('/v1')) {
          resolved = '$resolved/messages';
        } else {
          final separator = resolved.endsWith('/') ? '' : '/';
          resolved = '${resolved}${separator}messages';
        }
      }
      return Uri.parse(resolved);
    }

    var resolved = customBaseUrl.trim();
    if (resolved.isEmpty) {
      switch (provider) {
        case 'openai':
          resolved = 'https://api.openai.com/v1/chat/completions';
          break;
        case 'deepseek':
          resolved = 'https://api.deepseek.com/chat/completions';
          break;
        case 'ollama_custom':
        default:
          resolved = 'http://localhost:11434/v1/chat/completions';
          break;
      }
    }

    if (!resolved.contains('/chat/completions') &&
        !resolved.contains('/completions')) {
      if (resolved.endsWith('/v1')) {
        resolved = '$resolved/chat/completions';
      } else if (provider == 'ollama_custom' &&
          resolved.contains('11434') &&
          !resolved.contains('/v1')) {
        if (resolved.endsWith('/')) {
          resolved = '${resolved}v1/chat/completions';
        } else {
          resolved = '$resolved/v1/chat/completions';
        }
      } else if (resolved.endsWith('/')) {
        resolved = '${resolved}chat/completions';
      } else {
        resolved = '$resolved/chat/completions';
      }
    }
    return Uri.parse(resolved);
  }

  void close() => _client.close();
}

class GeminiService extends AiService {
  GeminiService({http.Client? client}) : super(client: client);
}

class GeneratedSlide {
  const GeneratedSlide({
    required this.title,
    required this.bullets,
    this.notes = '',
  });

  final String title;
  final List<String> bullets;
  final String notes;

  factory GeneratedSlide.fromJson(Map<String, Object?> json) {
    return GeneratedSlide(
      title: json['title']?.toString() ?? '',
      bullets: (json['bullets'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      notes: json['notes']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'bullets': bullets,
    'notes': notes,
  };
}

class GeneratedFlashcard {
  const GeneratedFlashcard({
    required this.question,
    required this.answer,
    this.topic = '',
  });

  final String question;
  final String answer;
  final String topic;

  factory GeneratedFlashcard.fromJson(Map<String, Object?> json) {
    return GeneratedFlashcard(
      question: json['question']?.toString() ?? '',
      answer: json['answer']?.toString() ?? '',
      topic: json['topic']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'question': question,
    'answer': answer,
    'topic': topic,
  };
}

class StructuredNote {
  const StructuredNote({required this.title, required this.sections});

  final String title;
  final List<StructuredSection> sections;

  factory StructuredNote.fromJson(Map<String, Object?> json) {
    final sections = json['sections'];
    if (sections is! List) {
      throw const GeminiException('AI did not return note sections.');
    }
    final parsedSections = sections
        .whereType<Map>()
        .map((item) => StructuredSection.fromJson(item.cast<String, Object?>()))
        .where((section) => section.heading.trim().isNotEmpty)
        .toList();
    if (parsedSections.isEmpty) {
      throw const GeminiException('AI returned no usable sections.');
    }
    return StructuredNote(
      title: json['title']?.toString().trim() ?? '',
      sections: parsedSections,
    );
  }
}

class StructuredSection {
  const StructuredSection({
    required this.heading,
    required this.body,
    required this.subsections,
  });

  final String heading;
  final List<String> body;
  final List<StructuredSection> subsections;

  factory StructuredSection.fromJson(Map<String, Object?> json) {
    return StructuredSection(
      heading: json['heading']?.toString() ?? '',
      body: _stringList(json['body']),
      subsections: (json['subsections'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => StructuredSection.fromJson(item.cast<String, Object?>()),
          )
          .where((section) => section.heading.trim().isNotEmpty)
          .toList(),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value == null) {
      return const [];
    }
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return value
        .toString()
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}

class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}
