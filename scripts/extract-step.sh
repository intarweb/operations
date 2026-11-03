#!/usr/bin/env bash
# Prints a workflow step's `run:` block, de-indented, with the GitHub
# expressions substituted from the environment.
#
#   extract-step.sh <workflow.yml> <step name substring> <VAR=value>...
#
# `${{ steps.X.outputs.Y }}` and `${{ vars.Y }}` are replaced from the given
# VARs (GitHub-style names), so a test can execute the block the runner
# executes instead of grepping its text.
set -euo pipefail
WF="${1:?usage: extract-step.sh <wf> <step> [VAR=value]...}"; shift
NEEDLE="${1:?step name substring}"; shift

python3 - "$WF" "$NEEDLE" "$@" <<'PY'
import sys, re, shlex, yaml
wf, needle = sys.argv[1], sys.argv[2]
subs = dict(a.split("=", 1) for a in sys.argv[3:])
doc = yaml.safe_load(open(wf))
steps = doc["jobs"]["publish"]["steps"]
step = next(s for s in steps if needle in s.get("name", ""))
body = step["run"]
lower = {k.lower(): v for k, v in subs.items()}
def rep(m):
    expr = m.group(1).strip()
    key = expr.split(".")[-1].lower()          # steps.tags.outputs.complete -> complete
    if expr in subs: return subs[expr]
    if key in lower: return lower[key]
    return ""                                  # unresolved -> empty, like an unset output
body = re.sub(r"\$\{\{(.*?)\}\}", rep, body)
lines = [l[10:] if l.startswith(" "*10) else l for l in body.split("\n")]
# The step's `env:` block is part of what the runner sets; export it so the
# block sees the same variables it sees in CI.
env = step.get("env") or {}
pre = []
for k, v in env.items():
    v = re.sub(r"\$\{\{(.*?)\}\}", rep, str(v))
    pre.append("export %s=%s" % (k, shlex.quote(v)))
print("\n".join(pre + lines))
PY
