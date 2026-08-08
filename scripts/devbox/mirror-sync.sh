#!/usr/bin/env bash
# mirror-sync.sh — re-scrub the mirror with the post-scrub fix and push to the target remote.
# This is the work the pre-push hook runs before `git push` to the public mirror.
# Idempotent. Re-runnable.
#
# Usage: mirror-sync.sh [REMOTE]
#   REMOTE defaults to "target" (the public github URL added on line 19+).
#   NOTE: do NOT default to "origin" — `git filter-repo` strips the origin remote,
#   so pushing to "origin" fails. Use "target" or pass an explicit remote name
#   that survives filter-repo (e.g. a remote pointing to the public URL).
set -euo pipefail

REMOTE="${1:-target}"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "[mirror-sync] clone worktree → /tmp/zet-scrub"
rm -rf /tmp/zet-scrub
git clone "$REPO_ROOT" /tmp/zet-scrub
cd /tmp/zet-scrub
git remote add target "https://github.com/rbelem/zet.git" 2>/dev/null || git remote set-url target "https://github.com/rbelem/zet.git"

echo "[mirror-sync] git filter-repo (apply replacements.txt)"
nix shell 'nixpkgs#git-filter-repo' --command bash -c '
  git filter-repo --replace-text '"$REPO_ROOT"'/replacements.txt --force
'

echo "[mirror-sync] strip ***REMOVED*** markers from scripts + tofu"
for f in scripts/fetch_vault.sh scripts/populate-sm.sh scripts/deploy.sh scripts/devbox/*.sh tofu/tofu-wrapper.sh; do
  [[ -f "$f" ]] || continue
  sed -i -E 's/^( *)(\*\*\*REMOVED\*\*\* *)/\1#/' "$f"
done
for f in tofu/*.tf; do
  [[ -f "$f" ]] || continue
  sed -i -E 's/^( *)(\*\*\*REMOVED\*\*\* *)/\1#/' "$f"
done

echo "[mirror-sync] chmod +x on deploy scripts"
chmod +x scripts/*.sh scripts/devbox/*.sh tofu/tofu-wrapper.sh

echo "[mirror-sync] commit in mirror + push to $REMOTE"
git add -A
git commit -m "fix: post-scrub + chmod +x" --allow-empty
git push "$REMOTE" --mirror --force

echo
echo "[mirror-sync] done. The push triggered gitleaks in CI."
echo "  Watch with:  gh run watch --repo rbelem/zet"
