#!/usr/bin/env bash
# scripts/lint-compose-secrets.sh
# CI gate: fail if any compose file gives a secret-looking variable a literal default (${VAR:-literal}),
# embeds credentials in a URL, or hardcodes a secret-named value. Use ${VAR:?msg} instead.
set -uo pipefail
rc=0; files=("$@"); [[ ${#files[@]} -gt 0 ]] || files=(docker-compose*.yml compose*.y*ml)
SECRET_NAME='(SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE|CREDENTIAL|DATABASE_URL|_DSN|CONN(ECTION)?_?STRING)'
for f in "${files[@]}"; do [[ -f $f ]] || continue
  src=$(mktemp); grep -vE '^\s*#' "$f" | nl -ba -w1 -s: > "$src"   # drop comment lines, keep line numbers
  # 1) ${NAME:-default} / ${NAME-default} where NAME is secret-like and default non-empty
  grep -nE "\\$\\{[A-Z0-9_]*${SECRET_NAME}[A-Z0-9_]*:?-[^}]+\\}" "$src" | sed "s|^|$f: secret-like var has literal default: |" && rc=1
  # 2) user:pass@host in any URL
  grep -nE '[a-z+]+://[^/ :@$]+:[^/ @$]+@' "$src" | grep -vE '://[^:]+:\$\{[A-Z_]+(:\?[^}]*)?\}@' | sed "s|^|$f: credentials embedded in URL: |" && rc=1
  # 3) KEY: literal / KEY=literal for secret-like names (not ${...} refs)
  grep -nE "^\s*-?\s*[A-Z0-9_]*${SECRET_NAME}[A-Z0-9_]*\s*[:=]\s*[\"']?[^\$\"' #][^\"' #]*" "$src" | sed "s|^|$f: hardcoded secret-like value: |" && rc=1
  rm -f "$src"
done
exit $rc
