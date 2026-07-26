***REMOVED***!/usr/bin/env bash
***REMOVED*** deploy.sh — one-command deploy cycle for the assistant repo.
***REMOVED***
***REMOVED*** This script consolidates the entire deploy flow into a single command:
***REMOVED*** 1. Re-scrub the mirror (filter-repo) + post-scrub fix
***REMOVED*** 2. Commit in the mirror (if anything changed)
***REMOVED*** 3. Print the push command (user does this; dcg blocks force-pushes)
***REMOVED*** 4. Wait for the user to push + watch gitleaks
***REMOVED*** 5. Once gitleaks is green, run fetch_vault.sh
***REMOVED*** 6. Run tofu init / plan / apply
***REMOVED*** 7. Run the initial deploy (nixos-infect + first nixos-rebuild as root)
***REMOVED*** 8. Verify
***REMOVED***
***REMOVED*** All destructive operations (tofu apply, push) are gated behind user
***REMOVED*** confirmation. dcg blocks the AI from running them, but the user
***REMOVED*** (with their master password and ssh-agent) can proceed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

MIRROR_DIR="/tmp/assistant-scrub"

***REMOVED*** ---- Phase 1: re-scrub the mirror with post-scrub fix ----
echo "==> Phase 1: re-scrub the mirror"
if [[ -d "$MIRROR_DIR" ]]; then
  echo "  Mirror directory exists, removing..."
  rm -rf "$MIRROR_DIR"
fi

git clone "$REPO_ROOT" "$MIRROR_DIR"
cd "$MIRROR_DIR"
git remote add public-origin https://github.com/rbelem/assistant.git 2>/dev/null || true

echo "  Running git filter-repo..."
devbox run -- git-filter-repo \
  --replace-text "$REPO_ROOT/replacements.txt" \
  --force

***REMOVED*** Strip ***REMOVED*** markers from script and tofu files
echo "  Stripping ***REMOVED*** markers..."
for f in scripts/fetch_vault.sh scripts/populate-vault.sh scripts/deploy.sh tofu/tofu-wrapper.sh; do
  if [[ -f "$f" ]]; then
    sed -i -E "s/^( *)(\*\*\*REMOVED\*\*\* *)/\1***REMOVED***/" "$f"
  fi
done
for f in tofu/*.tf; do
  if [[ -f "$f" ]]; then
    sed -i -E "s/^( *)(\*\*\*REMOVED\*\*\* *)/\1***REMOVED***/" "$f"
  fi
done

***REMOVED*** Re-apply the chmod +x (filter-repo wipes the permission)
echo "  Restoring executable permissions..."
chmod +x scripts/*.sh tofu/tofu-wrapper.sh 2>/dev/null || true

***REMOVED*** ---- Phase 2: commit in the mirror ----
echo "==> Phase 2: commit in the mirror"
git add scripts/ tofu/
if git diff --cached --quiet; then
  echo "  No changes to commit"
else
  git commit -m "fix(scripts+tofu): strip post-scrub ***REMOVED*** markers + chmod +x"
fi

cd "$REPO_ROOT"

***REMOVED*** ---- Phase 3: print the push command ----
echo "==> Phase 3: push the mirror to public"
echo
echo "Run these yourself (dcg blocks the AI from force-pushing):"
echo "  cd $MIRROR_DIR && git push public-origin --mirror --force"
echo
read -p "Press Enter when the push is done..."

***REMOVED*** ---- Phase 4: wait for gitleaks to pass ----
echo "==> Phase 4: watch gitleaks"
echo "  Watching GitHub Actions for gitleaks to pass..."
if ! devbox run -- gh run watch --repo rbelem/assistant; then
  echo
  echo "  ! gitleaks failed — check the run log:"
  echo "    devbox run -- gh run list --repo rbelem/assistant --workflow gitleaks --limit=1"
  echo "  Fix the leak, re-run this script, and try again."
  exit 1
fi
echo "  ✓ gitleaks passed"

***REMOVED*** ---- Phase 5: render vault.env ----
echo "==> Phase 5: render vault.env from Bitwarden"
if [[ -z "${BW_SESSION:-}" ]]; then
  echo
  echo "BW_SESSION is not set. Run:"
  echo "  export BW_SESSION=\$(bw unlock --raw)"
  echo "Then re-run this script."
  exit 1
fi

echo "  Fetching vault contents..."
scripts/fetch_vault.sh
echo "  ✓ vault.env rendered"

***REMOVED*** ---- Phase 6: tofu init / plan / apply ----
echo "==> Phase 6: provision the Hetzner VPS"
echo
echo "This will CREATE a real Hetzner VPS in Falkenstein (cx31, ~€17/mo)."
echo "The VPS will be billed to your Hetzner account."
echo
read -p "Continue with tofu apply? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  skipped tofu apply — re-run this script when ready"
  exit 0
fi

echo "  Running tofu init..."
tofu/tofu-wrapper.sh init

echo "  Running tofu plan..."
tofu/tofu-wrapper.sh plan -out=/tmp/tofu-plan.out

echo
echo "Review the plan above. This is your last chance to abort."
read -p "Apply this plan? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  skipped tofu apply"
  exit 0
fi

echo "  Running tofu apply..."
tofu/tofu-wrapper.sh apply /tmp/tofu-plan.out
echo "  ✓ VPS provisioned"

***REMOVED*** ---- Phase 7: initial deploy (nixos-infect + first nixos-rebuild as root) ----
echo "==> Phase 7: initial deploy (nixos-infect + first nixos-rebuild)"
echo
echo "The nix-config agent host must have these pre-applied:"
echo "  - services.openssh.settings.PermitRootLogin = \"no\""
echo "  - users.users.rodrigo = { ... openssh.authorizedKeys.keys = [ \"<your-pubkey>\" ] }"
echo
read -p "Is the nix-config agent host ready? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "  skipped initial deploy — make sure the nix-config agent host is ready, then re-run"
  exit 0
fi

echo "  Running initial deploy with INITIAL_SSH_USER=root..."
INITIAL_SSH_USER=root scripts/deploy.sh
echo "  ✓ initial deploy complete"

***REMOVED*** ---- Phase 8: verify ----
echo "==> Phase 8: verify"
echo
echo "Verify the deployment:"
echo "  1. Check the public repo:"
echo "     devbox run -- gh api repos/rbelem/assistant/contents/AGENTS.md --jq .content | head -50"
echo
echo "  2. SSH into the VPS and check k3s:"
VPS_IP=$(tofu output -raw vps_ip 2>/dev/null || echo "<vps-ip>")
echo "     ssh rodrigo@$VPS_IP kubectl get pods -A"
echo
echo "  3. Check the services:"
echo "     curl -I https://hermes.\$(jq -r .domain .rendered/runtime-config.json)"
echo
echo "Deploy complete! 🚀"
echo
echo "Subsequent deploys (no INITIAL_SSH_USER needed):"
echo "  scripts/deploy.sh"
