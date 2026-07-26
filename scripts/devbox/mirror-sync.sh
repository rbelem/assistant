***REMOVED***!/usr/bin/env bash
***REMOVED*** mirror-sync.sh — re-scrub the mirror with the post-scrub fix and push to public-origin.
***REMOVED*** This is the work the pre-push hook runs before `git push` to the public mirror.
***REMOVED*** Idempotent. Re-runnable.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "[mirror-sync] clone worktree → /tmp/assistant-scrub"
rm -rf /tmp/assistant-scrub
git clone "$REPO_ROOT" /tmp/assistant-scrub
cd /tmp/assistant-scrub
git remote add public-origin https://github.com/rbelem/assistant.git

echo "[mirror-sync] git filter-repo (apply replacements.txt)"
nix shell 'nixpkgs***REMOVED***git-filter-repo' --command bash -c '
  git filter-repo --replace-text '"$REPO_ROOT"'/replacements.txt --force
'

echo "[mirror-sync] strip ***REMOVED*** markers from scripts + tofu"
for f in scripts/fetch_vault.sh scripts/populate-vault.sh scripts/deploy.sh scripts/devbox/*.sh tofu/tofu-wrapper.sh; do
  [[ -f "$f" ]] || continue
  sed -i -E 's/^( *)(\*\*\*REMOVED\*\*\* *)/\1***REMOVED***/' "$f"
done
for f in tofu/*.tf; do
  [[ -f "$f" ]] || continue
  sed -i -E 's/^( *)(\*\*\*REMOVED\*\*\* *)/\1***REMOVED***/' "$f"
done

echo "[mirror-sync] chmod +x on deploy scripts"
chmod +x scripts/*.sh scripts/devbox/*.sh tofu/tofu-wrapper.sh

echo "[mirror-sync] commit in mirror + push to public-origin"
git add -A
git commit -m "fix: post-scrub + chmod +x" --allow-empty
git push public-origin --mirror --force

echo
echo "[mirror-sync] done. The push triggered gitleaks in CI."
echo "  Watch with:  gh run watch --repo rbelem/assistant"
