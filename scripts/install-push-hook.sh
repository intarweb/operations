#!/usr/bin/env bash
# Installs the intarweb pre-push dispatch hook into every intarweb fork clone,
# CHAINED with the fleet git-template dispatcher so the fleet commit gate is
# preserved (never overwritten).
#
# Why chained, not replaced: the fleet git-template (init.templateDir) already
# ships a pre-push dispatcher that injects each repo's own .githooks/pre-push
# (the non-ff-to-main + skill-drift/budget gate) into EVERY clone, fleet-wide.
# Git runs exactly ONE .git/hooks/pre-push per push, so this installer writes a
# single hook that (1) runs the repo's own gate if it ships one, then (2)
# dispatches intarweb build.yml on fork pushes. Existing fork clones are
# back-filled in place; the template itself is left untouched when it already
# carries the fleet dispatcher (Brokkr-owned, host-bootstrap substrate).
set -euo pipefail

CHAIN="$(cat <<'CHAIN'
#!/usr/bin/env bash
# Fleet git-template dispatcher + intarweb pre-push dispatch (chained by install-push-hook.sh).
# Per-clone and untracked: cannot enter a PR diff, cannot be erased by the
# hard-reset sync, does not touch core.hooksPath.
set -u

# --- 1. Fleet gate: run the repo's own .githooks/pre-push if it ships one. ---
# Matches the fleet template dispatcher's semantics; run (not exec) so a clean
# push falls through to the intarweb dispatch below. Fail-closed exactly like
# the dispatcher: a gate that exists but can't run blocks the push.
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$top" ] && [ -e "$top/.githooks/pre-push" ]; then
  hook="$top/.githooks/pre-push"
  if [ ! -x "$hook" ]; then
    printf '\npush blocked — %s exists but is not executable, so the repo gate cannot run.\nRestore it (chmod +x .githooks/pre-push), then re-push.\n' "$hook" >&2
    exit 1
  fi
  "$hook" "$@" || exit $?
fi

# --- 2. intarweb dispatch. ---
url="${2:-}"
case "$url" in
  *github.com[:/]intarweb/*) ;;
  *) exit 0 ;;                    # not ours — e.g. pushing to upstream
esac
repo="$(basename "${url%.git}")"
command -v gh >/dev/null 2>&1 || exit 0

# stdin: <local ref> <local sha> <remote ref> <remote sha>. An all-zero local
# sha is a branch deletion — nothing to build.
lines=0; live=0
while read -r _ local_sha _ _; do
  lines=$((lines + 1))
  case "$local_sha" in *[!0]*) live=1 ;; esac
done
# stdin can be empty on a non-fast-forward push without --force; fail open
# rather than silently swallowing the dispatch.
[ "$lines" -eq 0 ] && live=1
[ "$live" -eq 1 ] || exit 0

# pre-push fires BEFORE objects transfer; the fold reads PR head shas from
# origin and would otherwise see the pre-push state. Detached and silent —
# never blocks the push, never fails it. No --ref: runs build.yml from the
# fork's default branch, which is where it lives.
( sleep 15
  gh workflow run build.yml -R "intarweb/$repo"
) >/dev/null 2>&1 &
exit 0
CHAIN
)"

# Install into the template ONLY when it has no pre-push of its own. When it
# already carries the fleet dispatcher (the standard fleet state), leave it
# untouched — that file is Brokkr-owned (host-bootstrap substrate) and must not
# be clobbered. Existing clones still get the chained hook via the back-fill.
TEMPLATE="${GIT_TEMPLATE_DIR:-$HOME/.git-template}"
if [ -f "$TEMPLATE/hooks/pre-push" ]; then
  echo "template already has a pre-push hook ($TEMPLATE/hooks/pre-push) — leaving untouched"
  echo "  (existing clones get the chained hook below; template is Brokkr-owned)"
else
  mkdir -p "$TEMPLATE/hooks"
  printf '%s\n' "$CHAIN" > "$TEMPLATE/hooks/pre-push"
  chmod +x "$TEMPLATE/hooks/pre-push"
  git config --global init.templateDir "$TEMPLATE"
  echo "template installed: $TEMPLATE"
fi

# Back-fill existing clones: write the chained hook in place. Idempotent —
# re-running simply rewrites the same chain. Default to ~/src/intarweb/*/ when
# no clone dirs are given; pass dirs explicitly for a non-default layout.
if [ "$#" -eq 0 ]; then
  shopt -s nullglob
  set -- "$HOME"/src/intarweb/*/
  shopt -u nullglob
  [ "$#" -gt 0 ] || { echo "no clone dirs given and $HOME/src/intarweb/*/ is empty — pass clone dirs as args" >&2; exit 1; }
fi

for d in "$@"; do
  [ -d "$d/.git" ] || { echo "  (skip, not a repo: $d)"; continue; }
  printf '%s\n' "$CHAIN" > "$d/.git/hooks/pre-push"
  chmod +x "$d/.git/hooks/pre-push"
  echo "  back-filled: $d"
done
