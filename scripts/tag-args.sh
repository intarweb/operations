#!/usr/bin/env bash
# The tag argv for one buildx invocation. Sourced by the workflow and by
# scripts/test-fold-gates.sh, so the test executes the real construction
# instead of reimplementing it — a test that rebuilds the expected output can
# only prove its own copy right.
#
#   tag_names <complete|partial> <fp>   -> prints one tag name per line
#   tag_args  <image> <suffix> <names...> -> prints the argv, space separated
#
# The suffix applies to the TAG NAMES only. Expanding "${TAGS[@]/%/${sfx}}"
# over a mixed argv suffixes the `--tag` flags as well, producing `--tag-full`,
# which buildx rejects.
set -euo pipefail

tag_names() { # tag_names <complete|partial> <fp>
  case "$1" in
    complete) printf '%s\n' latest "sha-$2" ;;
    partial)  printf '%s\n' "partial-sha-$2" ;;
    *) echo "tag_names: unknown completeness '$1'" >&2; return 2 ;;
  esac
}

tag_args() { # tag_args <image> <suffix> <tag names...>
  local image="$1" sfx="$2"; shift 2
  local t
  for t in "$@"; do
    printf -- '--tag %s:%s%s ' "$image" "$t" "$sfx"
  done
}
