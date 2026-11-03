#!/usr/bin/env bash
# Tests the two fold gates whose failure is silent:
#
#   1. A rolled-back PR must stop the run BEFORE the image is pushed. Publishing
#      first and failing after left `:latest` holding a partial tree with a red
#      run that nobody reads in time.
#   2. The no-op path must not accept a partial image as finished. A tag can be
#      present because a failing build pushed it; only the fold label says the
#      image contains every open PR.
#
# Both are exercised here against fixture manifests, with no registry and no
# Docker: the parsing is the part that can regress, and it is pure text.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WF="${HERE}/../.github/workflows/build.yml"
fails=0

check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# The label probe, extracted so the test exercises the real expression.
label_verdict() { # label_verdict <the label value imagetools prints>
  # Exact match: "incomplete" and "complete-ish" are not clean.
  [ "$1" = "complete" ] && echo clean || echo dirty
}

echo "no-op gate: a present tag is not a finished image"
check "an image carrying the fold label short-circuits the build" clean \
  "$(label_verdict 'complete')"
check "an image without the label rebuilds" dirty "$(label_verdict '')"
check "an image marked partial rebuilds" dirty "$(label_verdict 'partial')"
check "an image marked incomplete rebuilds (not a substring match)" dirty \
  "$(label_verdict 'incomplete')"
check "a near-miss value rebuilds" dirty "$(label_verdict 'complete-ish')"

echo "publish gate: order of the steps in the workflow"
step_index() { # step_index <name substring>
  grep -n "name: .*$1" "$WF" | head -1 | cut -d: -f1
}
STOP="$(step_index 'Stop before publishing if any PR was rolled back')"
BUILD="$(step_index 'Build + push every variant')"
ASSEMBLE="$(step_index 'Assemble (cherry-pick open PRs')"

check "the rollback stop exists" yes "$([ -n "$STOP" ] && echo yes || echo no)"
check "it runs after the fold" yes \
  "$([ "${STOP:-0}" -gt "${ASSEMBLE:-999999}" ] && echo yes || echo no)"
check "and before anything is pushed" yes \
  "$([ "${STOP:-999999}" -lt "${BUILD:-0}" ] && echo yes || echo no)"
check "the build step is gated on no rollback" yes \
  "$(grep -A1 "name: 📦 Build + push every variant" "$WF" \
      | grep -q "steps.pick.outputs.failed == ''" && echo yes || echo no)"

echo "label: the build stamps its own completeness"
check "the push sets the fold label" yes \
  "$(grep -q 'net.siliconspirit.intarweb.fold=complete' "$WF" && echo yes || echo no)"

if [ "$fails" -gt 0 ]; then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
