# BLU-028 — Opt-in file indexing (partial)

The isolated `FileIndex` module starts disabled. Call `grant(directory, consent: true)` only after explicit user selection. It indexes UTF-8 files in that directory, excludes dot-prefixed path segments, does not follow symbolic links, and skips files larger than 1 MiB. `refresh()` updates indexed contents and removes deleted entries. `revoke()` immediately purges the in-memory index and invalidates scans. No network calls, model invocations or persistent indexed content exist in this module.

**Safety and limitations:** The folder chooser, user-facing toggle and accessibility/RTL review are not integrated yet; this is not an end-to-end feature. Permissions and offline conditions need platform integration evidence. Only a single selected directory is supported; arbitrary file selections are not yet supported. Byte contents are held in process memory and are not encrypted at rest because they are not stored on disk. Restart always defaults to disabled (new consent required). A file may change during reading; no filesystem watcher is installed. Symlinks are not followed during traversal.

**Rollback:** Disable the caller integration and invoke `revoke()`. Existing app behavior remains unchanged. No schema migration is required.
