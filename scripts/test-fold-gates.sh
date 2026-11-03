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
# The exact predicate the workflow runs, over fixtures shaped like a real
# `imagetools inspect --format '{{ json .Image }}'` on a multi-arch index:
# a map keyed by platform, each with its own config.Labels.
label_verdict() { # label_verdict <file>
  if jq -e 'to_entries
            | map(.value.config.Labels["net.siliconspirit.intarweb.fold"] // "MISSING")
            | length > 0 and all(. == "complete")' "$1" >/dev/null 2>&1; then
    echo clean
  else
    echo dirty
  fi
}

echo "no-op gate: a present tag is not a finished image"
check "every platform marked complete short-circuits the build" clean \
  "$(label_verdict "$HERE/fixtures/index-complete.json")"
check "one platform missing the label rebuilds" dirty \
  "$(label_verdict "$HERE/fixtures/index-one-missing.json")"
check "a platform marked incomplete rebuilds" dirty \
  "$(label_verdict "$HERE/fixtures/index-incomplete.json")"
check "no platform carrying the label rebuilds" dirty \
  "$(label_verdict "$HERE/fixtures/index-absent.json")"
check "unreadable output rebuilds" dirty "$(label_verdict /nonexistent.json)"
check "an empty map rebuilds" dirty \
  "$(printf '{}' > "$HERE/fixtures/.empty.json"; label_verdict "$HERE/fixtures/.empty.json")"
rm -f "$HERE/fixtures/.empty.json"

# The workflow's own tag-args text, executed. Everything below that needs the
# constructor uses this, so there is one definition in the whole suite.
BLOCK="$("$HERE/extract-tag-args.sh" "$WF")"
eval "$BLOCK"

echo "publish gate: a rolled-back build cannot take :latest or :sha-<fp>"
check "the tag decision exists and is keyed on the rollback list" yes \
  "$(grep -q "Decide the published tag set" "$WF" && grep -q 'steps.pick.outputs.failed' "$WF" && echo yes || echo no)"
check "a complete fold publishes :latest and :sha-<fp>" yes \
  "$(tag_names complete abc | tr '\n' ' ' | grep -qx 'latest sha-abc ' && echo yes || echo no)"
check "a rolled-back fold publishes :partial-sha-<fp> only" yes \
  "$(tag_names partial abc | tr '\n' ' ' | grep -qx 'partial-sha-abc ' && echo yes || echo no)"
check "the push uses the decided tag set" yes \
  "$(grep -qF 'TAGS[@]/%/' "$WF" && echo yes || echo no)"
check "no unconditional :latest tag survives in the push" yes \
  "$(grep -qF -- '--tag "ghcr.io/intarweb/${IMAGE}:latest${tag_sfx}"' "$WF" && echo no || echo yes)"
check "the run still goes red when a PR was rolled back" yes \
  "$(grep -q "Fail when the fold was incomplete" "$WF" && echo yes || echo no)"

echo "variant rows: the constructor as the REAL workflow text, executed"
# Extract the block the workflow itself runs, between its own markers, and
# execute that. Not a copy and not a reimplementation: this is the text that
# ships. A rendered expectation built here could only prove itself right.
check "the workflow carries a marked tag-args block" yes \
  "$(printf '%s' "$BLOCK" | grep -q 'tag_names()' && echo yes || echo no)"
argv() { # argv <complete|partial> <suffix>
  local names
  mapfile -t names < <(tag_names "$1" abc123)
  tag_args "ghcr.io/x/a" "$2" "${names[@]}" | sed 's/ $//'
}
check "complete, default: latest + sha, both flagged" \
  "--tag ghcr.io/x/a:latest --tag ghcr.io/x/a:sha-abc123" "$(argv complete '')"
check "complete, -full variant: flags stay flags" \
  "--tag ghcr.io/x/a:latest-full --tag ghcr.io/x/a:sha-abc123-full" "$(argv complete '-full')"
check "partial, default: partial tag only" \
  "--tag ghcr.io/x/a:partial-sha-abc123" "$(argv partial '')"
check "partial, -full variant: partial only, suffixed" \
  "--tag ghcr.io/x/a:partial-sha-abc123-full" "$(argv partial '-full')"
check "no suffixed argv contains a mangled flag" yes \
  "$(argv complete '-full' | grep -q -- '--tag-' && echo no || echo yes)"
check "every element of a suffixed argv is --tag or a tag" yes \
  "$(argv complete '-full' | tr ' ' '\n' | grep -v '^$' | grep -qvE '^(--tag|ghcr\.io/)' && echo no || echo yes)"

echo "caller context: this workflow is reusable, so it must not read the caller's tree"
# workflow_call means GITHUB_WORKSPACE is the CALLER's checkout. Anything this
# workflow sources from there exists when the test runs inside operations and
# does not exist when a fork runs the workflow — the failure mode that makes a
# locally-green test meaningless.
check "the workflow sources nothing from GITHUB_WORKSPACE" yes \
  "$(grep -q 'source .*GITHUB_WORKSPACE' "$WF" && echo no || echo yes)"
check "the workflow sources nothing from its own scripts/ dir at run time" yes \
  "$(grep -qE '^\s*source .*\$\{?(HERE|GITHUB_WORKSPACE)' "$WF" && echo no || echo yes)"
check "the tag constructor is inline in the workflow, not a separate file" yes \
  "$(grep -q 'tag_names()' "$WF" && echo yes || echo no)"
check "no tag-args script is expected to exist in a caller checkout" yes \
  "$([ -e "$HERE/tag-args.sh" ] && echo no || echo yes)"

echo "label: the build stamps its own completeness"
check "the push sets the fold label" yes \
  "$(grep -q 'net.siliconspirit.intarweb.fold=complete' "$WF" && echo yes || echo no)"

if [ "$fails" -gt 0 ]; then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
