import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Verified local model store core (#281, child of #198).
///
/// Storage and download state machine only. It never ships production asset
/// metadata, never picks a default model, and never starts a download unless
/// [ModelStore.install] is called explicitly. Voice processing must not call
/// it as a side effect. No native worker, microphone or inference is involved.

/// The manifest version this build understands.
const modelManifestVersion = 1;

/// One caller-supplied model asset description.
class ModelAsset {
  /// Creates an asset description.
  const ModelAsset({
    required this.id,
    required this.revision,
    required this.bytes,
    required this.sha256Hex,
    required this.format,
    required this.backend,
    required this.licenseNotice,
    this.languages = const [],
  });

  /// Reads one asset from manifest JSON; throws [FormatException] if invalid.
  factory ModelAsset.fromJson(Map<String, dynamic> json) {
    String str(String key) {
      final v = json[key];
      if (v is! String) throw FormatException('asset.$key must be a string');
      return v;
    }

    final size = json['bytes'];
    if (size is! int) throw const FormatException('asset.bytes must be an int');
    final langs = json['languages'];
    return ModelAsset(
      id: str('id'),
      revision: str('revision'),
      bytes: size,
      sha256Hex: str('sha256'),
      format: str('format'),
      backend: str('backend'),
      licenseNotice: json['licenseNotice'] is String
          ? json['licenseNotice'] as String
          : '',
      languages: langs is List ? langs.whereType<String>().toList() : const [],
    );
  }

  /// Stable asset id, e.g. a model family name.
  final String id;

  /// Revision label; one id can have several revisions.
  final String revision;

  /// Exact size in bytes.
  final int bytes;

  /// Expected lowercase hex SHA-256 of the file.
  final String sha256Hex;

  /// File format, checked against the store's accepted formats.
  final String format;

  /// Inference backend this asset targets, checked against the store.
  final String backend;

  /// License or notice text. Required: an asset without one is rejected.
  final String licenseNotice;

  /// Language codes the asset supports.
  final List<String> languages;

  /// Collision-free, directory-safe key per id and revision. Each part is
  /// base64url (no '.'), so distinct pairs such as a/b and a_b never collide.
  String get key =>
      '${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}.'
      '${base64Url.encode(utf8.encode(revision)).replaceAll('=', '')}';

  /// Immutable, content-unique file name: the key plus a digest prefix. A
  /// different digest under the same id and revision gets a different file,
  /// so a leased file's contents never change under its holder.
  String get fileName {
    final sha = sha256Hex.length >= 32 ? sha256Hex.substring(0, 32) : sha256Hex;
    return '$key.$sha';
  }
}

/// A versioned list of assets supplied by the caller.
class ModelManifest {
  /// Creates a manifest.
  const ModelManifest({required this.version, required this.assets});

  /// Parses manifest JSON; unknown versions throw [FormatException].
  factory ModelManifest.parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('manifest must be an object');
    }
    final version = json['version'];
    if (version != modelManifestVersion) {
      throw FormatException('unsupported manifest version: $version');
    }
    final list = json['assets'];
    if (list is! List) throw const FormatException('manifest.assets missing');
    return ModelManifest(
      version: version as int,
      assets: [
        for (final a in list) ModelAsset.fromJson(a as Map<String, dynamic>),
      ],
    );
  }

  /// Manifest version.
  final int version;

  /// Assets listed.
  final List<ModelAsset> assets;
}

/// Why an install did or did not activate.
enum ModelInstallResult {
  /// Verified and now the active asset.
  activated,

  /// The asset was already active; nothing changed.
  alreadyActive,

  /// Format or backend not accepted by this store.
  incompatible,

  /// License or notice metadata missing.
  missingLicense,

  /// Malformed metadata (size or digest).
  invalidMetadata,

  /// Free space below the asset size.
  insufficientSpace,

  /// Downloaded size differs from the manifest.
  wrongSize,

  /// Digest differs; the partial file was discarded.
  hashMismatch,

  /// Cancelled; the partial file is kept for resume.
  cancelled,

  /// The transfer broke; the partial file is kept for resume.
  interrupted,
}

/// Cooperative cancel flag for [ModelStore.install].
class ModelCancelToken {
  bool _cancelled = false;

  /// Whether cancel was requested.
  bool get isCancelled => _cancelled;

  /// Requests cancel.
  void cancel() => _cancelled = true;
}

/// Opens the asset bytes starting at [offset]. Injected; the store never
/// opens a network connection itself.
typedef ModelDownloader = Stream<List<int>> Function(
  ModelAsset asset,
  int offset,
);

/// Returns free bytes on the volume holding the store.
typedef FreeSpaceProbe = Future<int> Function();

/// A hold on the active asset. While any lease is open the asset's files stay.
class ModelLease {
  ModelLease._(this._store, this.asset, this.path);

  final ModelStore _store;

  /// The leased asset.
  final ModelAsset asset;

  /// File path valid until [release].
  final String path;
  bool _released = false;

  /// Releases the lease; files pending delete are removed when none remain.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _store._release(this);
  }
}

/// The store. All paths live under the injected [root].
///
/// Safe-removal policy: selection changes immediately and never points at a
/// removed or unverified asset. Files of an asset with open leases are
/// deleted when the last lease is released, never while in use.
class ModelStore {
  /// Creates a store rooted at [root].
  ModelStore({
    required this.root,
    required this.downloader,
    required this.freeSpace,
    this.acceptedFormats = const {},
    this.acceptedBackends = const {},
  }) {
    _live[_rootKey] = this;
  }

  static Stream<List<int>> _noDownloads(ModelAsset a, int o) =>
      throw StateError('no downloader configured');
  static Future<int> _noSpace() async => 0;

  /// Store directory.
  final Directory root;

  /// Injected transfer source.
  final ModelDownloader downloader;

  /// Injected free-space probe.
  final FreeSpaceProbe freeSpace;

  /// Formats this store accepts. Empty accepts none.
  final Set<String> acceptedFormats;

  /// Backends this store accepts. Empty accepts none.
  final Set<String> acceptedBackends;

  final Map<String, int> _leases = {};
  final Set<String> _pendingDelete = {};
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  static final Map<String, ModelStore> _live = {};

  /// Runs [fn] after every earlier mutation finished. Selection, lease and
  /// delete changes never interleave.
  Future<T> _run<T>(Future<T> Function() fn) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) => fn()).whenComplete(done.complete);
  }

  /// Stops this store being the live owner for its folder (tests, teardown).
  void dispose() {
    if (identical(_live[_rootKey], this)) _live.remove(_rootKey);
  }

  String get _rootKey => root.absolute.path;

  Directory get _assets => Directory('${root.path}/assets');
  Directory get _partial => Directory('${root.path}/partial');
  File get _selection => File('${root.path}/selection.json');

  /// Reads the persisted verified selection, or null if none or broken.
  /// A selection whose file is missing or the wrong size is ignored.
  Future<ModelAsset?> activeAsset() async {
    if (!_selection.existsSync()) return null;
    try {
      final json = jsonDecode(await _selection.readAsString());
      final asset = ModelAsset.fromJson(json as Map<String, dynamic>);
      final file = File('${_assets.path}/${asset.fileName}');
      if (!file.existsSync() || file.lengthSync() != asset.bytes) return null;
      return asset;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Downloads (resuming a kept partial), verifies size and hash, then
  /// activates atomically. Any failure leaves the previous selection intact.
  Future<ModelInstallResult> install(
    ModelAsset asset, {
    ModelCancelToken? cancel,
  }) async {
    if (asset.licenseNotice.trim().isEmpty) {
      return ModelInstallResult.missingLicense;
    }
    if (asset.bytes <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.sha256Hex)) {
      return ModelInstallResult.invalidMetadata;
    }
    if (!acceptedFormats.contains(asset.format) ||
        !acceptedBackends.contains(asset.backend)) {
      return ModelInstallResult.incompatible;
    }
    final generation = _generation;
    final current = await activeAsset();
    if (current != null && current.fileName == asset.fileName) {
      return ModelInstallResult.alreadyActive;
    }
    bool stale() => generation != _generation;
    await _partial.create(recursive: true);
    await _assets.create(recursive: true);
    if (stale()) return ModelInstallResult.cancelled;
    final part = File('${_partial.path}/${asset.fileName}.part');
    var have = part.existsSync() ? part.lengthSync() : 0;
    if (have > asset.bytes) {
      await part.delete();
      have = 0;
    }
    if (await freeSpace() < asset.bytes - have) {
      return ModelInstallResult.insufficientSpace;
    }
    if (have < asset.bytes) {
      final sink = part.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in downloader(asset, have)) {
          if ((cancel?.isCancelled ?? false) || stale()) {
            await sink.close();
            return ModelInstallResult.cancelled;
          }
          sink.add(chunk);
        }
        await sink.close();
      } on Object {
        try {
          await sink.close();
        } on Object {
          // Already failed; the partial stays for a later resume.
        }
        return ModelInstallResult.interrupted;
      }
      if ((cancel?.isCancelled ?? false) || stale()) {
        return ModelInstallResult.cancelled;
      }
    }
    if (!part.existsSync()) {
      return stale()
          ? ModelInstallResult.cancelled
          : ModelInstallResult.interrupted;
    }
    if (part.lengthSync() != asset.bytes) {
      // Short transfers resume later; overlong ones are corrupt.
      if (part.lengthSync() > asset.bytes) {
        await part.delete();
        return ModelInstallResult.wrongSize;
      }
      return ModelInstallResult.interrupted;
    }
    Digest digest;
    try {
      digest = await sha256.bind(part.openRead()).first;
    } on FileSystemException {
      return stale()
          ? ModelInstallResult.cancelled
          : ModelInstallResult.interrupted;
    }
    if (stale()) return ModelInstallResult.cancelled;
    if (digest.toString() != asset.sha256Hex) {
      if (part.existsSync()) await part.delete();
      return ModelInstallResult.hashMismatch;
    }
    // Commit is serialized and re-checks the generation: a delete that ran
    // while this install was downloading or hashing wins.
    return _run(() async {
      if (stale() || !part.existsSync()) return ModelInstallResult.cancelled;
      final target = File('${_assets.path}/${asset.fileName}');
      await part.rename(target.path);
      await _writeSelection(asset);
      _pendingDelete.remove(asset.fileName);
      await _pruneInactive(keep: asset.fileName);
      return ModelInstallResult.activated;
    });
  }

  Future<void> _writeSelection(ModelAsset asset) async {
    final tmp = File('${root.path}/selection.json.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'id': asset.id,
        'revision': asset.revision,
        'bytes': asset.bytes,
        'sha256': asset.sha256Hex,
        'format': asset.format,
        'backend': asset.backend,
        'licenseNotice': asset.licenseNotice,
        'languages': asset.languages,
      }),
      flush: true,
    );
    await tmp.rename(_selection.path);
  }

  /// Opens a lease on the active asset, or null when none is active.
  /// Lookup and lease registration are one serialized step, so a switch or
  /// delete cannot remove the file between them.
  Future<ModelLease?> acquire() => _run(() async {
    final asset = await activeAsset();
    if (asset == null) return null;
    final name = asset.fileName;
    _leases[name] = (_leases[name] ?? 0) + 1;
    return ModelLease._(this, asset, '${_assets.path}/$name');
  });

  Future<void> _release(ModelLease lease) => _run(() async {
    final key = lease.asset.fileName;
    final left = (_leases[key] ?? 1) - 1;
    if (left <= 0) {
      _leases.remove(key);
      if (_pendingDelete.remove(key)) await _deleteFiles(key);
    } else {
      _leases[key] = left;
    }
  });

  Future<void> _deleteFiles(String key) async {
    final file = File('${_assets.path}/$key');
    if (file.existsSync()) await file.delete();
  }

  /// Removes every verified file except [keep]; leased ones wait for release.
  /// Runs inside the serialized commit.
  Future<void> _pruneInactive({required String keep}) async {
    if (!_assets.existsSync()) return;
    for (final entity in _assets.listSync()) {
      if (entity is! File) continue;
      final key = entity.uri.pathSegments.last;
      if (key == keep) continue;
      if ((_leases[key] ?? 0) > 0) {
        _pendingDelete.add(key);
      } else {
        await entity.delete();
      }
    }
  }

  /// Removes the active asset and clears the selection. Files in use wait for
  /// the last lease; the selection is cleared now so it cannot come back.
  Future<void> removeActive() {
    _generation++;
    return _run(() async {
      final asset = await activeAsset();
      if (_selection.existsSync()) await _selection.delete();
      if (asset == null) return;
      final name = asset.fileName;
      if ((_leases[name] ?? 0) > 0) {
        _pendingDelete.add(name);
      } else {
        await _deleteFiles(name);
      }
    });
  }

  /// Deletes everything: selection, verified files and partials. Leased files
  /// are removed on release. A deleted selection is never resurrected.
  Future<void> deleteAll() {
    _generation++;
    return _run(() async {
      if (_selection.existsSync()) await _selection.delete();
      final tmp = File('${root.path}/selection.json.tmp');
      if (tmp.existsSync()) await tmp.delete();
      if (_partial.existsSync()) await _partial.delete(recursive: true);
      if (_assets.existsSync()) {
        for (final entity in _assets.listSync()) {
          if (entity is! File) continue;
          final key = entity.uri.pathSegments.last;
          if ((_leases[key] ?? 0) > 0) {
            _pendingDelete.add(key);
          } else {
            await entity.delete();
          }
        }
      }
    });
  }

  /// Registry clear: deletes the on-disk store under the app support folder
  /// (or [supportDir] when injected). A live store on that folder owns its
  /// leases, so the clear goes through it; files still leased are removed on
  /// release. Nothing to delete when no platform folder exists (tests).
  static Future<void> clearOnDisk({Directory? supportDir}) async {
    try {
      final base = supportDir ?? await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/models');
      final live = _live[dir.absolute.path];
      if (live != null) {
        await live.deleteAll();
        return;
      }
      if (!dir.existsSync()) return;
      final temp = ModelStore(
        root: dir,
        downloader: _noDownloads,
        freeSpace: _noSpace,
      );
      try {
        await temp.deleteAll();
      } finally {
        temp.dispose();
      }
    } on MissingPluginException {
      // No platform channel, so no store exists either.
    }
  }

  /// Inventory for the privacy screen: id, revision and size of the active
  /// asset plus bytes held in partial transfers. Empty when nothing is stored.
  Future<Map<String, Object>> inventory() async {
    final asset = await activeAsset();
    var partialBytes = 0;
    if (_partial.existsSync()) {
      for (final e in _partial.listSync()) {
        if (e is File) partialBytes += e.lengthSync();
      }
    }
    return {
      if (asset != null) 'active': '${asset.id}@${asset.revision}',
      if (asset != null) 'activeBytes': asset.bytes,
      'partialBytes': partialBytes,
    };
  }
}
