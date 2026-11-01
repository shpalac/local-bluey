# Vendored flutter_secure_storage_linux 1.2.3

- Official archive: https://pub.dev/api/archives/flutter_secure_storage_linux-1.2.3.tar.gz
- Archive size: 141756 bytes
- Archive SHA-256: `be76c1d24a97d0b98f8b54bce6b481a380a6590df992d0098f868ad54dc8f688`
- Source fix: https://github.com/juliansteenbakker/flutter_secure_storage/pull/923
- Upstream merge commit: `d97758ec900a1aaf5022ccc1617c916cb062380e`
- Reproduction: https://github.com/juliansteenbakker/flutter_secure_storage/issues/965
- Archive package LICENSE: BSD 3-Clause; bundled `linux/include/json.hpp`: MIT.
- Modification: precisely four user-defined-literal whitespace substitutions in `linux/include/json.hpp`; no warning suppression, behavior change, or other package-file modifications.
- Original (unpatched) json.hpp Git blob SHA-1: `dbbe68458d99a3c632628b8df21c65cdd85e27af`.
- Patched json.hpp Git blob SHA-1: `14945d1b049f02f1547e9d66bda06749e280f14f`.

## Reproduce the vendored source

```bash
set -euo pipefail
curl -fL 'https://pub.dev/api/archives/flutter_secure_storage_linux-1.2.3.tar.gz' -o /tmp/flutter_secure_storage_linux-1.2.3.tar.gz
printf '%s  %s\n' 'be76c1d24a97d0b98f8b54bce6b481a380a6590df992d0098f868ad54dc8f688' /tmp/flutter_secure_storage_linux-1.2.3.tar.gz | sha256sum -c -
mkdir -p /tmp/flutter-secure-storage-linux-original
tar -xzf /tmp/flutter_secure_storage_linux-1.2.3.tar.gz -C /tmp/flutter-secure-storage-linux-original
cd /tmp/flutter-secure-storage-linux-original
patch --forward -p1 < "${REPOSITORY_ROOT}/docs/vendor/flutter-secure-storage-linux-923.patch"
diff -ruN . "${REPOSITORY_ROOT}/third_party/flutter_secure_storage_linux"
```

The last diff must be empty. Set `REPOSITORY_ROOT` to the absolute checkout path before invoking the recipe. The vendored local package retains the original `pubspec.yaml`, platform declarations, and bundled licenses. The root `pubspec.yaml` overrides this Linux implementation by relative path while retaining the v9 umbrella API. The root `pubspec.lock` is intentionally **not edited** in this intermediate commit; pinned Flutter 3.47.6 resolution is required separately.
