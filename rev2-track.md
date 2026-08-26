# Build pipeline rev 2 — tracking checklist + log

> Per the rev-2 mission brief (from Justin). Update §2 in-place as you go;
> commit the doc each time a box flips. Waves land one per PR (never batched),
> each independently revertible. A wave is done when its §9 gate passes, not
> when its file is pushed. If a gate fails twice → stop and report.
>
> Authored + merged by Idunn (fleet merge-coordinator) under explicit Justin
> authorization. In-flight truths, not promises — verify against the live
> artifact before relying.

## §2 Checklist

- [x] **W1 — F5 authenticated no-op check + F6 registry cache** (`b9830be`, ops PR #2)
  - F5: login above no-op; no-op via `docker buildx imagetools inspect` (needs auth). Verified on 4 canaries (acme.sh, mcp-neo4j, unifi-*.5min, metamcp): no-op skips rebuild, login now always runs.
  - F6: `cache-to: type=registry,ref=...:buildcache,mode=max` / `cache-from` (not `type=gha`). Verified real rebuild on acme.sh (REBUILD_EPOCH=1) imported the cache manifest.
- [x] **W2 — F2 all-or-nothing rollback + F3 no -X theirs, fail-closed** (`617d41e`, ops PR #3)
  - F2: per-PR `BASE=$(git rev-parse HEAD)`, linearize via `rev-list --no-merges --reverse`, on any pick failure `git reset --hard "$BASE"` + record under `failed=`.
  - F3: removed `-X theirs`; LAST step `❌ Fail if any PR was rolled back` (`exit 1`). Verified on synthetic conflicting PR (#356, closed): whole PR rolled back, run red, `❌ Fail` line present.
- [x] **W3 — F4 fingerprint covers build inputs + F7 OCI labels** (`3468728`, ops PR #4)
  - F4: `V_DOCKERFILE/V_CONTEXT/V_PLATFORMS/V_BUILD_ARGS/V_REBUILD_EPOCH` via env into the fingerprint. Verified acme.sh forced rebuild with a new fingerprint.
  - F7: OCI labels `source/revision/version/description` on published image. Verified all four on acme.sh published image.
- [x] **W4 — workflow_dispatch in consumer + pre-push dispatch hook** (`f0b97ca` PR #5 + `4bc0306` PR #6)
  - Consumer already had `workflow_dispatch` + `uses: ...@main` + `secrets: inherit` → per §4, changed nothing and recorded.
  - Hook: `scripts/install-push-hook.sh` installs a per-clone pre-push hook that runs the repo's own `.githooks/pre-push` (fleet gate) then dispatches `build.yml` on intarweb pushes. Fixed during install to CHAIN with the fleet dispatcher, never clobber it (template is Brokkr-owned via host-bootstrap).
  - §9 gate: real push on a fork → `workflow_dispatch` run within ~30s. Verified on metamcp: dispatch `32953913247` created ~15s after push, completed success.

## Log

### W4 (2026-08-26)
- Landed `scripts/install-push-hook.sh` (PR #5) + fix (PR #6) — installer now chains the
  intarweb pre-push dispatch with the fleet git-template dispatcher instead of overwriting it.
  The template's `pre-push` is Brokkr-owned (host-bootstrap substrate) and is left untouched;
  existing fork clones are back-filled with the chained hook in place. Verified the template
  stayed byte-identical and the clone hook is a working chain (non-intarweb push = silent
  no-op; intarweb push = background `gh workflow run build.yml`).
- §9 W4 gate PASSED: real push on `intarweb/metamcp` (`w4-hook-gate`, now deleted) produced
  `workflow_dispatch` run `32953913247` created ~15s after the push; completed **success**.
  Hook → dispatch → build → no-op path green end-to-end.
- Earlier failure at 09:16Z (`32952086230`) is pre-hook and in the fork's legacy `publish`
  job, not the build — parked for W6, not W4.
- Installer usage: `scripts/install-push-hook.sh [clone-dir...]` (defaults to `~/src/intarweb/*/`).

### W1 (2026-08-25)
- F5 + F6 landed and verified (see §2). F6 cache-import observed on acme.sh real rebuild.
### W2 (2026-08-25)
- F2 + F3 landed and verified (synthetic conflicting PR #356). 
### W3 (2026-08-25)
- F4 + F7 landed and verified (acme.sh forced rebuild, all four OCI labels).
