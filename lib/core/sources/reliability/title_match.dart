/// Title matching for source search results.
///
/// Normalizes width/case/punctuation, extracts season/episode numbers (Arabic
/// and Chinese numerals) and scores a candidate title against a query. It is
/// deliberately dependency-free so it can rank results before any network
/// probe happens.
class TitleMatch {
  const TitleMatch({required this.score, this.season, this.episode});

  /// 0..1; 1 means the base titles and both numbering fields agree.
  final double score;
  final int? season;
  final int? episode;

  bool get isConfident => score >= TitleMatcher.confidentScore;
}

class TitleMatcher {
  TitleMatcher._();

  /// Below this, auto-pick should not choose the source without the user.
  static const double confidentScore = 0.7;

  static final RegExp _numbering = RegExp(
    r'(?:s\s*(\d{1,3})\s*e\s*(\d{1,3}))'
    r'|(?:season\s*(\d{1,3}))'
    r'|(?:episode\s*(\d{1,3}))'
    r'|第\s*([0-9一二三四五六七八九十百零两]+)\s*[季部]'
    r'|第\s*([0-9一二三四五六七八九十百零两]+)\s*[集话話]',
    caseSensitive: false,
  );

  static final RegExp _punctuation = RegExp(
    r'[\s\-_:：·.,，。!！?？/\\()\[\]【】「」『』~～]+',
  );

  static TitleMatch score(String query, String candidate) {
    final q = _ParsedTitle.parse(query);
    final c = _ParsedTitle.parse(candidate);
    var score = similarity(q.base, c.base);
    if (q.season != null && c.season != null) {
      score += q.season == c.season ? 0.15 : -0.50;
    }
    if (q.episode != null && c.episode != null) {
      score += q.episode == c.episode ? 0.10 : -0.40;
    }
    return TitleMatch(
      score: score.clamp(0.0, 1.0),
      season: c.season,
      episode: c.episode,
    );
  }

  /// Levenshtein-based similarity, after normalizing both sides.
  static double similarity(String a, String b) {
    final left = normalizeTitle(a);
    final right = normalizeTitle(b);
    if (left == right) return 1;
    if (left.isEmpty || right.isEmpty) return 0;
    final distance = _levenshtein(left, right);
    final longest = left.length > right.length ? left.length : right.length;
    return (1 - distance / longest).clamp(0.0, 1.0);
  }

  /// Lowercase, half-width, punctuation-free base title.
  static String normalizeTitle(String raw) =>
      _ParsedTitle.parse(raw).base;

  static ({int? season, int? episode}) parseNumbering(String raw) {
    final parsed = _ParsedTitle.parse(raw);
    return (season: parsed.season, episode: parsed.episode);
  }

  static int _levenshtein(String a, String b) {
    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = _min3(
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        );
      }
      previous.setAll(0, current);
    }
    return previous[b.length];
  }

  static int _min3(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }
}

class _ParsedTitle {
  const _ParsedTitle({required this.base, this.season, this.episode});

  final String base;
  final int? season;
  final int? episode;

  static _ParsedTitle parse(String raw) {
    final halfWidth = _toHalfWidth(raw).toLowerCase();
    int? season;
    int? episode;
    for (final match in TitleMatcher._numbering.allMatches(halfWidth)) {
      if (match.group(1) != null) {
        season ??= int.tryParse(match.group(1)!);
        episode ??= int.tryParse(match.group(2)!);
      } else if (match.group(3) != null) {
        season ??= int.tryParse(match.group(3)!);
      } else if (match.group(4) != null) {
        episode ??= int.tryParse(match.group(4)!);
      } else if (match.group(5) != null) {
        season ??= _number(match.group(5)!);
      } else if (match.group(6) != null) {
        episode ??= _number(match.group(6)!);
      }
    }
    final base = halfWidth
        .replaceAll(TitleMatcher._numbering, ' ')
        .replaceAll(TitleMatcher._punctuation, '')
        .trim();
    return _ParsedTitle(base: base, season: season, episode: episode);
  }

  static String _toHalfWidth(String input) {
    final buffer = StringBuffer();
    for (final code in input.runes) {
      if (code == 0x3000) {
        buffer.write(' ');
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        buffer.writeCharCode(code - 0xFEE0);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  static int? _number(String raw) {
    if (RegExp(r'^\d+$').hasMatch(raw)) return int.tryParse(raw);
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    var section = 0;
    var number = 0;
    for (final char in raw.split('')) {
      final digit = digits[char];
      if (digit != null) {
        number = digit;
      } else if (char == '十') {
        section += (number == 0 ? 1 : number) * 10;
        number = 0;
      } else if (char == '百') {
        section += (number == 0 ? 1 : number) * 100;
        number = 0;
      } else {
        return null;
      }
    }
    final result = section + number;
    return result == 0 && raw != '零' ? null : result;
  }
}
