#!/usr/bin/env bash
# Prints the tag-args block out of the workflow, exactly as the workflow runs
# it. The test evaluates this text; it does not carry its own copy.
#
# The block is delimited by `# tag-args:begin` / `# tag-args:end` inside the
# build step, so extraction follows the workflow's own marker rather than
# guessing at indentation.
set -euo pipefail
WF="${1:?usage: extract-tag-args.sh <workflow.yml>}"
awk '/# tag-args:begin/{f=1; next} /# tag-args:end/{f=0} f' "$WF" | sed 's/^          //'
