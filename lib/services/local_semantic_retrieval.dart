import 'dart:async';
import 'dart:math' as math;

import 'file_index.dart';

/// A path-backed excerpt, produced exclusively from consented FileIndex data.
class LocalRetrievalHit {
  const LocalRetrievalHit({
    required this.path,
    required this.excerpt,
    required this.score,
  });

  final String path;
  final String excerpt;
  final double score;
}

enum LocalRetrievalStatus {
  ready,
  disabled,
  invalidQuery,
  noMatches,
  cancelled,
  timedOut,
}

class LocalRetrievalResult {
  const LocalRetrievalResult(this.status, this.hits);

  final LocalRetrievalStatus status;
  final List<LocalRetrievalHit> hits;
}

/// An intentionally local, deterministic hashed-token embedding. No model,
/// HTTP client, telemetry, persistent vectors or OS permission is created.
/// Replaceable with a native on-device embedding model in a later change.
class LocalSemanticRetriever {
  const LocalSemanticRetriever(this.index);

  final FileIndex index;

  static const int _dimensions = 256;
  static final RegExp _tokens = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  static List<String> _words(String source) => _tokens
      .allMatches(source.toLowerCase())
      .map((match) => match.group(0)!)
      .toList(growable: false);

  static List<double> _embed(String source) {
    final vector = List<double>.filled(_dimensions, 0);
    for (final token in _words(source)) {
      // Stable 32-bit FNV-1a, independent of Dart's hashCode randomization.
      var hash = 2166136261;
      for (final rune in token.runes) {
        hash = ((hash ^ rune) * 16777619) & 0xffffffff;
      }
      vector[hash % _dimensions] += 1;
    }
    final length = math.sqrt(vector.fold<double>(0, (s, x) => s + x * x));
    if (length > 0) {
      for (var i = 0; i < vector.length; i++) {
        vector[i] /= length;
      }
    }
    return vector;
  }

  static double _similarity(List<double> left, List<double> right) {
    var score = 0.0;
    for (var i = 0; i < _dimensions; i++) {
      score += left[i] * right[i];
    }
    return score;
  }

  /// Search only the active, user-granted index snapshot.
  /// Revocation or index refresh during retrieval invalidates the response.
  Future<LocalRetrievalResult> retrieve(
    String query, {
    int limit = 5,
    Duration timeout = const Duration(seconds: 2),
    Future<bool> Function()? isCancelled,
  }) async {
    if (!index.isEnabled || index.state != FileIndexState.ready) {
      return const LocalRetrievalResult(LocalRetrievalStatus.disabled, []);
    }
    if (query.trim().isEmpty ||
        limit < 1 ||
        limit > 50 ||
        timeout <= Duration.zero) {
      return const LocalRetrievalResult(LocalRetrievalStatus.invalidQuery, []);
    }
    final snapshot = index.retrievalSnapshot();
    if (snapshot.isEmpty) {
      return const LocalRetrievalResult(LocalRetrievalStatus.noMatches, []);
    }
    final queryVector = _embed(query);
    if (_words(query).isEmpty) {
      return const LocalRetrievalResult(LocalRetrievalStatus.invalidQuery, []);
    }
    final hits = <LocalRetrievalHit>[];
    final clock = Stopwatch()..start();
    for (final entry in snapshot.entries) {
      if (!index.isEnabled ||
          index.state != FileIndexState.ready ||
          !index.matchesRetrievalSnapshot(snapshot)) {
        return const LocalRetrievalResult(LocalRetrievalStatus.cancelled, []);
      }
      if (clock.elapsed >= timeout) {
        return const LocalRetrievalResult(LocalRetrievalStatus.timedOut, []);
      }
      if (isCancelled != null && await isCancelled()) {
        return const LocalRetrievalResult(LocalRetrievalStatus.cancelled, []);
      }
      // Rank bounded excerpts, rather than allowing long files to drown out
      // relevant passages. Every excerpt is copied from the indexed content.
      final source = entry.value;
      const chunkSize = 480;
      const stride = 360;
      for (var start = 0; start < source.length; start += stride) {
        if (clock.elapsed >= timeout) {
          return const LocalRetrievalResult(LocalRetrievalStatus.timedOut, []);
        }
        final end = math.min(start + chunkSize, source.length);
        final excerpt = source.substring(start, end);
        final score = _similarity(queryVector, _embed(excerpt));
        if (score > 0) {
          hits.add(
            LocalRetrievalHit(path: entry.key, excerpt: excerpt, score: score),
          );
        }
      }
    }
    if ((isCancelled != null && await isCancelled()) ||
        !index.isEnabled ||
        index.state != FileIndexState.ready ||
        !index.matchesRetrievalSnapshot(snapshot)) {
      return const LocalRetrievalResult(LocalRetrievalStatus.cancelled, []);
    }
    if (clock.elapsed >= timeout) {
      return const LocalRetrievalResult(LocalRetrievalStatus.timedOut, []);
    }
    hits.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.path.compareTo(b.path);
    });
    return LocalRetrievalResult(
      hits.isEmpty
          ? LocalRetrievalStatus.noMatches
          : LocalRetrievalStatus.ready,
      List.unmodifiable(hits.take(limit)),
    );
  }
}
