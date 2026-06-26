# Fork tracking — intarweb/__UPSTREAM_REPO__

This is a soft fork of [`<UPSTREAM-FULL>`](https://github.com/<UPSTREAM-FULL>). We track upstream HEAD daily and <publish to GHCR | carry patches that haven't landed upstream yet | ...>.

> All forks we manage with the sync-upstream + from-source-build pattern live under the [`intarweb`](https://github.com/intarweb) GitHub org. See the `ghcr-fork-mirror` skill for the canonical recipe.

## Branch model

| Branch | Purpose | Source of truth |
|---|---|---|
| `main` | <Upstream-clean tracking | Deploy track> | upstream OR us |
| `intarweb-dev` (if Model B) | Deploy track. Rebased daily onto `upstream/<x>` with our local patches on top. | us |
| `feat/*`, `fix/*` (if any) | Individual patch branches we PR upstream | us |

## Upstream sync

| Property | Value |
|---|---|
| Upstream | [`<UPSTREAM-FULL>`](https://github.com/<UPSTREAM-FULL>) |
| Upstream branch tracked | `__UPSTREAM_BRANCH__` |
| Sync cadence | Daily 06:<MIN> UTC + manual `workflow_dispatch` |
| Sync mechanism | `git rebase upstream/__UPSTREAM_BRANCH__` then `git push --force-with-lease` |
| Sync workflow | [`.github/workflows/sync-upstream.yml`](.github/workflows/sync-upstream.yml) |

## Build pipeline

| Property | Value |
|---|---|
| Image | `ghcr.io/intarweb/<GHCR-NAME>` |
| `:latest` source | <push to main | push to intarweb-dev | upstream's existing publish-ghcr.yml | our build-from-source.yml> |
| `:sha-<short>` (or `:sha-<long>`) | Every build |
| Tagged releases (`v*`) | Mirror upstream's release tags via fork-publish.yml |
| Multi-arch | <e.g. linux/amd64, linux/arm64, ...> |
| Build workflow | [`.github/workflows/<name>.yml`](.github/workflows/<name>.yml) |
| Smoke gate | <description of what passes/fails the gate> |

## Local patches we carry on `__DEPLOY_BRANCH__` (vs `upstream/__UPSTREAM_BRANCH__`)

| Commit | Subject | Status |
|---|---|---|
| `<sha>` | `<commit subject>` | <Open PR #X | Not yet PRed | Fork-only> |

## How to consume

\`\`\`yaml
# docker-compose.yml
services:
  <service>:
    image: ghcr.io/intarweb/<GHCR-NAME>:latest
\`\`\`

Pin to a specific build for reproducibility:

\`\`\`yaml
    image: ghcr.io/intarweb/<GHCR-NAME>:sha-<short>
\`\`\`

## Maintenance recipes

**Manually re-sync onto upstream:**
\`\`\`bash
gh workflow run "Sync from upstream" --repo intarweb/__UPSTREAM_REPO__
\`\`\`

**Force a fresh build of `:latest` without an upstream change:**
\`\`\`bash
gh workflow run "<build-workflow-name>" --repo intarweb/__UPSTREAM_REPO__ --ref __DEPLOY_BRANCH__
\`\`\`

**Add a new patch to intarweb-dev (Model B only):**
\`\`\`bash
git checkout -b feat/my-thing upstream/__UPSTREAM_BRANCH__
# ...do work...
git push origin feat/my-thing
gh pr create --repo <UPSTREAM-FULL> --base __UPSTREAM_BRANCH__ --head intarweb:feat/my-thing
git checkout intarweb-dev && git merge feat/my-thing
git push origin intarweb-dev   # triggers publish; :latest gets the new patch
# (also add a row to FORK_INFO.md table above)
\`\`\`
