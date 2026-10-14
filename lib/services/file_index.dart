import 'dart:async';
import 'dart:io';

/// Indexing is disabled until the caller explicitly grants a directory.
enum FileIndexState { disabled, indexing, ready, denied, cancelled, failed }

/// Ephemeral local-only index. No file bytes or paths are sent to providers.
/// A restart drops all grants and indexed contents.
class FileIndex {
  FileIndex({
    this.maxBytes = 1024 * 1024,
    this.timeout = const Duration(seconds: 20),
  });

  final int maxBytes;
  final Duration timeout;
  FileIndexState state = FileIndexState.disabled;
  final Map<String, String> _contents = {};
  final Map<String, DateTime> _modified = {};
  String? _root;
  int _generation = 0;

  int get documentCount => _contents.length;

  /// Read-only in-memory snapshot; no independent filesystem access.
  Map<String, String> retrievalSnapshot() =>
      _root != null && state == FileIndexState.ready
          ? Map.unmodifiable(_contents)
          : const {};

  /// A revoked or refreshed index must not emit stale citations.
  bool matchesRetrievalSnapshot(Map<String, String> snapshot) {
    if (_root == null || state != FileIndexState.ready ||
        snapshot.length != _contents.length) return false;
    for (final entry in snapshot.entries) {
      if (_contents[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool get isEnabled => _root != null;
  List<String> search(String query) {
    if (_root == null || query.trim().isEmpty) return const [];
    final needle = query.toLowerCase();
    return List.unmodifiable(
      _contents.entries
          .where((entry) => entry.value.toLowerCase().contains(needle))
          .map((entry) => entry.key),
    );
  }

  /// Only call after an explicit directory-selection UI and consent.
  /// Symlinked directories/files are never followed.
  Future<void> grant(Directory directory, {required bool consent}) async {
    if (!consent) {
      state = FileIndexState.denied;
      return;
    }
    if (!await directory.exists()) {
      state = FileIndexState.failed;
      throw const FileSystemException('Selected directory unavailable');
    }
    revoke();
    _root = await directory.resolveSymbolicLinks();
    await refresh();
  }

  Future<void> refresh() async {
    final root = _root;
    if (root == null) throw StateError('File indexing requires consent');
    final ticket = ++_generation;
    state = FileIndexState.indexing;
    final contents = <String, String>{};
    final modified = <String, DateTime>{};
    try {
      await _scan(Directory(root), contents, modified, ticket).timeout(timeout);
      if (ticket != _generation) {
        return;
      }
      _contents
        ..clear()
        ..addAll(contents);
      _modified
        ..clear()
        ..addAll(modified);
      state = FileIndexState.ready;
    } on TimeoutException {
      if (ticket == _generation) state = FileIndexState.failed;
      rethrow;
    } catch (_) {
      if (ticket == _generation) state = FileIndexState.failed;
      rethrow;
    }
  }

  Future<void> _scan(
    Directory root,
    Map<String, String> contents,
    Map<String, DateTime> modified,
    int ticket,
  ) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (ticket != _generation) return;
      final relative = entity.path.substring(root.path.length + 1);
      if (relative
          .split(Platform.pathSeparator)
          .any((segment) => segment.startsWith('.'))) {
        continue;
      }
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file || stat.size > maxBytes) {
        continue;
      }
      if (_modified[entity.path] == stat.modified &&
          _contents.containsKey(entity.path)) {
        contents[entity.path] = _contents[entity.path]!;
      } else {
        try {
          contents[entity.path] = await entity.readAsString();
        } on FormatException {
          continue; // Binary/non-UTF8 files are not indexed.
        } on FileSystemException {
          continue; // Inaccessible files are not indexed.
        }
      }
      modified[entity.path] = stat.modified;
    }
  }

  /// Purge synchronously before any outstanding scan may publish results.
  void revoke() {
    ++_generation;
    _root = null;
    _contents.clear();
    _modified.clear();
    state = FileIndexState.disabled;
  }

  static final FileIndex instance = FileIndex();
}
