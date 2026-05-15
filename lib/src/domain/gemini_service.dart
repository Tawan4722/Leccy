import 'dart:convert';

import 'package:http/http.dart' as http;

class GeminiService {
  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<GeneratedSlide>> generateSlides({
    required String apiKey,
    required String title,
    required String noteText,
  }) async {
    final json = await _generateJson(
      apiKey: apiKey,
      prompt:
          'Create a concise lecture presentation as JSON with key "slides". '
          'Each slide must have "title", "bullets" as an array of strings, '
          'and optional "notes". Use 4 to 8 slides.\n\n'
          'Lecture title: $title\n\nNotes:\n$noteText',
    );
    final slides = json['slides'];
    if (slides is! List) {
      throw const GeminiException('Gemini did not return slides.');
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
  }) async {
    final json = await _generateJson(
      apiKey: apiKey,
      prompt:
          'Create study flashcards as JSON with key "cards". Each card must '
          'have "question", "answer", and "topic". Use 8 to 16 cards.\n\n'
          'Lecture title: $title\n\nNotes:\n$noteText',
    );
    final cards = json['cards'];
    if (cards is! List) {
      throw const GeminiException('Gemini did not return flashcards.');
    }
    return cards
        .whereType<Map>()
        .map(
          (item) => GeneratedFlashcard.fromJson(item.cast<String, Object?>()),
        )
        .where((card) => card.question.trim().isNotEmpty)
        .toList();
  }

  Future<Map<String, Object?>> _generateJson({
    required String apiKey,
    required String prompt,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      throw const GeminiException('Enter a Gemini API key in Settings first.');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-flash:generateContent',
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': cleanKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {'responseMimeType': 'application/json'},
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiException('Gemini request failed: ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final candidates = decoded is Map ? decoded['candidates'] : null;
    final content = candidates is List && candidates.isNotEmpty
        ? candidates.first['content']
        : null;
    final parts = content is Map ? content['parts'] : null;
    final text = parts is List && parts.isNotEmpty ? parts.first['text'] : null;
    if (text is! String || text.trim().isEmpty) {
      throw const GeminiException('Gemini returned an empty response.');
    }
    final parsed = jsonDecode(text);
    if (parsed is! Map) {
      throw const GeminiException('Gemini returned invalid JSON.');
    }
    return parsed.cast<String, Object?>();
  }

  void close() => _client.close();
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

class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}
