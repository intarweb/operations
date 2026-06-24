# intarweb/operations

Operational automation for the [intarweb](https://github.com/intarweb) fork pool.

**Public on purpose:** these workflows only *read* the public intarweb forks, and a
public repo gets unlimited GitHub Actions minutes. They previously lived in private
`terafin/claude`, where every run drew down the metered free tier and eventually hit a
billing block — relocated here 2026-06-24.

## Workflows

| Workflow | Schedule | Purpose |
|---|---|---|
| `portfolio-audit.yml` | daily 14:00 UTC + dispatch | Snapshot every `intarweb/*` fork (workflows present, `intarweb-dev` branch, sync-upstream + build-from-source run states, open intarweb→upstream PRs); diff vs prior snapshot; commit a drift digest. |
| `portfolio-auto-heal.yml` | daily 14:15 UTC + on audit success + dispatch | Auto-fix detected drift (re-template missing workflows, kick stalled sync-upstream, etc.). |
| `portfolio-build-health.yml` | dispatch | Build-health spot-check across the pool. |

Output (drift digests + JSON snapshots) is committed to `validation-queue/` in this repo.

## Credentials

No repo-level secrets needed — the workflows authenticate as the **intarweb-sync-bot
GitHub App** via org-level `vars.SYNC_APP_ID` + `secrets.SYNC_APP_PRIVATE_KEY`
(both `visibility=all` on the intarweb org, inherited automatically). Drift-report
commits are unsigned (no `BOT_SIGNING_KEY` here — it was terafin/claude-local).

## Source of truth

The portfolio-audit *logic* is documented in the `oss-contributing:intarweb-portfolio-audit`
skill (terafin/claude). This repo is the *runtime* home.
