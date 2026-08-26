#!/usr/bin/env bash
# Installs the intarweb pre-push dispatch hook into the git template dir, so
# every FUTURE clone (yours or an agent's) gets it, then back-fills existing ones.
set -euo pipefail

TEMPLATE="${GIT_TEMPLATE_DIR:-$HOME/.git-template}"
mkdir -p "$TEMPLATE/hooks"

cat > "$TEMPLATE/hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
# .git/hooks/pre-push — dispatch the fork's build.yml after a push lands.
# Per-clone and untracked: cannot enter a PR diff, cannot be erased by the
# hard-reset sync, does not touch core.hooksPath.
set -euo pipefail

# $1 = remote name, $2 = remote URL.
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
HOOK

chmod +x "$TEMPLATE/hooks/pre-push"
git config --global init.templateDir "$TEMPLATE"
echo "template installed: $TEMPLATE"

# Back-fill existing clones. `git init` in place is the documented way to pick
# up newly added templates and will NOT overwrite anything already present —
# which is also why we delete the old hook first when updating it.
for d in "${@:-$HOME/src/intarweb/*/}"; do
  [ -d "$d/.git" ] || continue
  rm -f "$d/.git/hooks/pre-push"
  git -C "$d" init >/dev/null
  echo "  back-filled: $d"
done
