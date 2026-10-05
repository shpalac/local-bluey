#!/usr/bin/env bash
# Pattern scan over native (Swift/Kotlin/etc.) sources for hardcoded
# secrets (#160). Complements gitleaks (which scans git history) with a
# focused pass over the native trees, matching what review actually
# catches: API keys, bearer tokens, private-key headers, cloud keys.
#
# Usage: scan-native-secrets.sh [dir ...]   (default: macos ios android linux)
set -euo pipefail
dirs=("$@")
[ ${#dirs[@]} -gt 0 ] || dirs=(macos ios android linux)

pattern='(api[_-]?key|api[_-]?secret|access[_-]?token|auth[_-]?token|secret[_-]?key|client[_-]?secret|private[_-]?key)[A-Za-z0-9_ -]{0,20}(=|:)[[:space:]]*"[^"]{8,}"|-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|sk-[A-Za-z0-9_-]{20,}'

hits=0
for dir in "${dirs[@]}"; do
  [ -d "$dir" ] || continue
  if command -v rg >/dev/null 2>&1; then
    scan=(rg -i --no-heading -e "$pattern"
      -g '*.swift' -g '*.kt' -g '*.kts' -g '*.java' -g '*.m' -g '*.mm'
      -g '*.cc' -g '*.cpp' -g '*.h' -g '*.plist' -g '*.gradle' "$dir")
  else
    # ripgrep is not guaranteed on every runner; never pass silently.
    scan=(grep -rniE -e "$pattern"
      --include='*.swift' --include='*.kt' --include='*.kts' --include='*.java'
      --include='*.m' --include='*.mm' --include='*.cc' --include='*.cpp'
      --include='*.h' --include='*.plist' --include='*.gradle' "$dir")
  fi
  if "${scan[@]}"; then
    hits=1
  fi
done

if [ "$hits" -ne 0 ]; then
  echo "hardcoded-secret pattern(s) found in native sources - see above" >&2
  exit 1
fi
echo "native secrets scan: clean (${dirs[*]})"
