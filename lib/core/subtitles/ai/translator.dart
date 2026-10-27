/// Translation interfaces and the offline cost estimate.
///
/// The pipeline never calls a provider directly: [Translator] is the seam, and
/// the first implementation is `ClaudeTranslator`. Everything here is pure so
/// batching and costing are unit-testable without network access.
library;

import 'transcript.dart';

class TranslationException implements Exception {
  const TranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A request-sized slice of the transcript, with neighbouring lines attached
/// as read-only context so the model keeps the dialogue coherent.
class TranslationBatch {
  const TranslationBatch({
    required this.segments,
    this.contextBefore = const [],
    this.contextAfter = const [],
  });

  final List<TranscriptSegment> segments;
  final List<TranscriptSegment> contextBefore;
  final List<TranscriptSegment> contextAfter;

  List<int> get ids => [for (final segment in segments) segment.id];
}

class TranslationRequest {
  const TranslationRequest({
    required this.batch,
    this.glossary = const {},
    this.sourceLanguage,
  });

  final TranslationBatch batch;
  final Map<String, String> glossary;
  final String? sourceLanguage;

  List<int> get ids => batch.ids;
}

class TranslationResult {
  const TranslationResult({
    required this.translations,
    this.fallbackIds = const {},
  });

  /// id -> Chinese text. Contains every id of the batch: ids the model kept
  /// failing on are filled with the original text.
  final Map<int, String> translations;

  /// Ids that fell back to the original text after the retry.
  final Set<int> fallbackIds;

  String? operator [](int id) => translations[id];
}

abstract interface class Translator {
  /// Model identifier used for the cost estimate and for display.
  String get model;

  /// Extracts names/terms and their fixed Chinese rendering once per video.
  Future<Map<String, String>> extractGlossary(List<TranscriptSegment> segments);

  /// Translates one batch. Implementations must fill every id of the batch,
  /// falling back to the original text when a line cannot be aligned.
  Future<TranslationResult> translate(TranslationRequest request);
}

/// Splits the transcript into translation batches of [batchSize] segments,
/// each with up to [contextSize] neighbouring lines as context.
List<TranslationBatch> buildTranslationBatches(
  List<TranscriptSegment> segments, {
  int batchSize = 40,
  int contextSize = 5,
}) {
  if (batchSize <= 0) {
    throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
  }
  final batches = <TranslationBatch>[];
  for (var start = 0; start < segments.length; start += batchSize) {
    final end = start + batchSize < segments.length
        ? start + batchSize
        : segments.length;
    final beforeStart = start - contextSize < 0 ? 0 : start - contextSize;
    final afterEnd = end + contextSize < segments.length
        ? end + contextSize
        : segments.length;
    batches.add(TranslationBatch(
      segments: segments.sublist(start, end),
      contextBefore:
          beforeStart == start ? const [] : segments.sublist(beforeStart, start),
      contextAfter:
          afterEnd == end ? const [] : segments.sublist(end, afterEnd),
    ));
  }
  return batches;
}

/// Rough token and price estimate shown to the user before translation.
///
/// The numbers are deliberately approximate: they are computed from the
/// transcript length (about four characters per token for Latin text, one per
/// CJK character) plus per-batch prompt overhead, and priced with the public
/// pay-as-you-go rates of the Haiku/Sonnet/Opus families.
class AiSubtitleCostEstimate {
  const AiSubtitleCostEstimate({
    required this.model,
    required this.segmentCount,
    required this.batchCount,
    required this.estimatedInputTokens,
    required this.estimatedOutputTokens,
    required this.estimatedUsd,
  });

  final String model;
  final int segmentCount;
  final int batchCount;
  final int estimatedInputTokens;
  final int estimatedOutputTokens;
  final double estimatedUsd;

  /// `$0.012`-style label for the confirmation dialog.
  String get usdLabel => '\$${estimatedUsd.toStringAsFixed(3)}';
}

AiSubtitleCostEstimate estimateTranslationCost(
  List<TranscriptSegment> segments,
  String translatorModel, {
  int batchSize = 40,
}) {
  final pricing = _pricingFor(translatorModel);
  var sourceTokens = 0;
  for (final segment in segments) {
    sourceTokens += _tokenCount(segment.text);
  }
  final batches =
      segments.isEmpty ? 0 : (segments.length + batchSize - 1) ~/ batchSize;
  // Direct translation cost plus the one-shot glossary pass, the per-batch
  // prompt/instructions and the duplicated context lines.
  final inputTokens = (sourceTokens * 1.2).round() + 300 + batches * 120;
  final outputTokens = (sourceTokens * 1.3).round() + segments.length * 4;
  final usd = inputTokens / 1000000 * pricing.inputPerMillion +
      outputTokens / 1000000 * pricing.outputPerMillion;
  return AiSubtitleCostEstimate(
    model: translatorModel,
    segmentCount: segments.length,
    batchCount: batches,
    estimatedInputTokens: inputTokens,
    estimatedOutputTokens: outputTokens,
    estimatedUsd: usd,
  );
}

class _Pricing {
  const _Pricing(this.inputPerMillion, this.outputPerMillion);

  final double inputPerMillion;
  final double outputPerMillion;
}

const _haikuPricing = _Pricing(1, 5);
const _sonnetPricing = _Pricing(3, 15);
const _opusPricing = _Pricing(15, 75);

/// Unknown model names fall back to Haiku pricing, which under-estimates
/// rather than surprising the user with a larger bill.
_Pricing _pricingFor(String model) {
  final lower = model.toLowerCase();
  if (lower.contains('sonnet')) return _sonnetPricing;
  if (lower.contains('opus')) return _opusPricing;
  return _haikuPricing;
}

/// 4 Latin characters or 1 CJK character per token, rounded up.
int _tokenCount(String text) {
  var cjk = 0;
  var other = 0;
  for (final rune in text.runes) {
    if (rune >= 0x2E80) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + ((other + 3) ~/ 4);
}
