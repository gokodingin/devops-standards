#!/usr/bin/env bash
# scripts/push-secrets.sh
# Validate an untracked dotenv file and push it as the APP_ENV GitHub *Environment* secret without
# secrets ever touching argv, shell history, or git. Prints key NAMES only.
#
# Usage: push-secrets.sh -r owner/repo -e production -f .env.production [-k required-keys.txt] [-n]
#   -r repo  -e GitHub Environment name  -f env file (dotenv)  -k file listing required keys
#   -n dry-run (validate only)
set -euo pipefail
umask 077
repo= envname= file= req= dry=0
while getopts r:e:f:k:n o; do case $o in
  r) repo=$OPTARG;; e) envname=$OPTARG;; f) file=$OPTARG;; k) req=$OPTARG;; n) dry=1;;
  *) sed -n '2,8p' "$0"; exit 2;; esac; done
[[ -n $repo && -n $envname && -f $file ]] || { sed -n '2,8p' "$0"; exit 2; }
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "bad repo" >&2; exit 2; }
[[ $envname =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "bad environment name" >&2; exit 2; }

# 1. file hygiene: not tracked, owner-only perms
if git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then echo "REFUSE: $file is tracked by git" >&2; exit 1; fi
perm=$(stat -c %a "$file"); [[ $perm =~ ^[46]00$ ]] || { echo "REFUSE: $file mode $perm (need 600/400)" >&2; exit 1; }

# 2. parse keys (names only; values never printed)
mapfile -t keys < <(grep -vE '^\s*(#|$)' "$file" | sed -E 's/^export +//' | cut -d= -f1)
bad=0
for k in "${keys[@]}"; do [[ $k =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "invalid key name: $k" >&2; bad=1; }
  [[ $k == GITHUB_* ]] && { echo "reserved prefix GITHUB_: $k" >&2; bad=1; }; done
dup=$(printf '%s\n' "${keys[@]}" | sort | uniq -d); [[ -z $dup ]] || { echo "duplicate keys: $dup" >&2; bad=1; }
# empty values & placeholder / known-weak values
while IFS='=' read -r k v; do v=${v%\"}; v=${v#\"}
  [[ -z $v ]] && { echo "empty value: $k" >&2; bad=1; }
  [[ $v =~ ^(changeme|change_me|password|secret|postgres|dev_.*|local_.*|xxx+|todo)$ ]] && { echo "placeholder/weak value: $k" >&2; bad=1; }
done < <(grep -vE '^\s*(#|$)' "$file" | sed -E 's/^export +//')
if [[ -n $req ]]; then
  while read -r r; do [[ -z $r || $r == \#* ]] && continue
    printf '%s\n' "${keys[@]}" | grep -qx "$r" || { echo "missing required key: $r" >&2; bad=1; }; done < "$req"
fi
[[ $bad -eq 0 ]] || exit 1
echo "validated ${#keys[@]} keys for $repo/$envname:"; printf '  %s\n' "${keys[@]}"
[[ $dry -eq 1 ]] && { echo "dry-run: nothing pushed"; exit 0; }

# 3. push as ONE environment secret (APP_ENV) via stdin: values never in argv, new keys need no workflow change
gh secret set APP_ENV -R "$repo" --env "$envname" < "$file" >/dev/null
echo "pushed APP_ENV (${#keys[@]} keys) to $repo environment '$envname'"
