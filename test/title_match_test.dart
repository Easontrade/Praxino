import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/reliability/title_match.dart';

void main() {
  test('normalizes case, width and punctuation', () {
    expect(TitleMatcher.normalizeTitle('Ｂｒｅａｋｉｎｇ　Ｂａｄ'),
        'breakingbad');
    expect(TitleMatcher.normalizeTitle('Breaking Bad: Season 1'),
        'breakingbad');
    expect(TitleMatcher.normalizeTitle('【示例】 第2季'), '示例');
  });

  test('parses Arabic, SxxExx and Chinese numbering', () {
    expect(TitleMatcher.parseNumbering('第3季 第12集'), (season: 3, episode: 12));
    expect(TitleMatcher.parseNumbering('S02E07'), (season: 2, episode: 7));
    expect(TitleMatcher.parseNumbering('第二季 第三集'),
        (season: 2, episode: 3));
    expect(TitleMatcher.parseNumbering('第十季 第十集'),
        (season: 10, episode: 10));
    expect(TitleMatcher.parseNumbering('没有集数'), (season: null, episode: null));
  });

  test('similarity is punctuation-insensitive and ordered', () {
    expect(TitleMatcher.similarity('Breaking Bad', 'breaking bad!'), 1.0);
    expect(TitleMatcher.similarity('abc', 'abd'), closeTo(2 / 3, 0.001));
    expect(TitleMatcher.similarity('abc', 'xyz'), 0.0);
  });

  test('score prefers the same season and episode', () {
    final exact = TitleMatcher.score('示例剧 第二季 第3集', '示例剧 第2季 第03集');
    final wrongSeason =
        TitleMatcher.score('示例剧 第二季 第3集', '示例剧 第5季 第03集');
    final wrongEpisode =
        TitleMatcher.score('示例剧 第二季 第3集', '示例剧 第2季 第09集');

    expect(exact.score, greaterThan(0.95));
    expect(exact.season, 2);
    expect(exact.episode, 3);
    expect(wrongSeason.score, lessThan(exact.score));
    expect(wrongEpisode.score, lessThan(exact.score));
    expect(wrongSeason.score, lessThan(TitleMatcher.confidentScore));
  });

  test('a different title is not confident even with matching numbering', () {
    final other = TitleMatcher.score('Breaking Bad S01E01', 'Better Call Saul S01E01');
    expect(other.score, lessThan(TitleMatcher.confidentScore));
    expect(other.season, 1);
    expect(other.episode, 1);
  });
}
