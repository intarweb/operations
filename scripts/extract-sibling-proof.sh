#!/usr/bin/env bash
# Prints the sibling-proof function out of the workflow, exactly as the
# workflow runs it. The test evaluates this text; it does not carry its own
# copy, so the two cannot drift.
#
# Delimited by `# sibling-proof:begin` / `# sibling-proof:end` inside the
# assemble step, the same idiom extract-tag-args.sh uses.
set -euo pipefail
WF="${1:?usage: extract-sibling-proof.sh <workflow.yml>}"
awk '/# sibling-proof:begin/{f=1; next} /# sibling-proof:end/{f=0} f' "$WF" \
  | sed 's/^          //'
