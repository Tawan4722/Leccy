import 'dart:convert';

class SummaryService {
  static const int _maxSentences = 3;
  static const int _minWordsForAuto = 40;
  static const int _minChangeThreshold = 40;

  String sourceHash({
    required String title,
    required String noteText,
    required String quickNote,
  }) {
    final source = '${title.trim()}\n${noteText.trim()}\n${quickNote.trim()}';
    return source.hashCode.toString();
  }

  bool shouldAutoSummarize({
    required String sourceHash,
    required String? previousHash,
    required String sourceText,
  }) {
    if (previousHash == sourceHash) {
      return false;
    }
    final wordCount = _wordCount(sourceText);
    if (wordCount < _minWordsForAuto) {
      return false;
    }
    return true;
  }

  bool changedEnough({
    required String previousSource,
    required String nextSource,
  }) {
    final delta = (nextSource.length - previousSource.length).abs();
    return delta >= _minChangeThreshold;
  }

  String summarize({
    required String title,
    required String noteText,
    required String quickNote,
  }) {
    final cleanTitle = title.trim();
    final cleanNote = noteText.trim();
    final cleanQuick = quickNote.trim();

    final combined = [
      if (cleanTitle.isNotEmpty) cleanTitle,
      if (cleanQuick.isNotEmpty) cleanQuick,
      if (cleanNote.isNotEmpty) cleanNote,
    ].join('. ');

    if (combined.isEmpty) {
      return '';
    }

    final sentences = _splitSentences(combined);
    if (sentences.isEmpty) {
      return _truncate(combined);
    }

    final frequencies = _wordFrequency(sentences);
    final scored = <_ScoredSentence>[];
    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final words = _tokenize(sentence);
      var score = 0.0;
      for (final word in words) {
        score += frequencies[word] ?? 0;
      }
      scored.add(_ScoredSentence(i, sentence, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(_maxSentences).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final summary = top.map((item) => item.text.trim()).join(' ');
    return _truncate(summary);
  }

  String plainTextFromQuillJson(String contentJson) {
    try {
      final decoded = jsonDecode(contentJson);
      if (decoded is! List) {
        return '';
      }
      final buffer = StringBuffer();
      for (final op in decoded) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert'] as String);
        }
      }
      return buffer.toString().replaceAll('\n', ' ').trim();
    } catch (_) {
      return '';
    }
  }

  List<String> _splitSentences(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return const [];
    }
    return normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Map<String, double> _wordFrequency(List<String> sentences) {
    final frequencies = <String, double>{};
    for (final sentence in sentences) {
      for (final token in _tokenize(sentence)) {
        frequencies[token] = (frequencies[token] ?? 0) + 1;
      }
    }
    return frequencies;
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
  }

  int _wordCount(String text) {
    return text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  String _truncate(String text) {
    const maxChars = 260;
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxChars).trimRight()}...';
  }
}

class _ScoredSentence {
  _ScoredSentence(this.index, this.text, this.score);

  final int index;
  final String text;
  final double score;
}
