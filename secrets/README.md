# secrets/ (pf-db, local-only)

Module-scoped, machine-local secrets for the Neon dump/restore workflow.
Everything placed in this folder — including new subfolders — is gitignored
by default (see `.gitignore` right here): only this `README.md`, the
`.gitignore` itself, and the `neon.env.example` template can ever be
committed.

## Current contents

| Path | Committed? | Used by |
| --- | --- | --- |
| `neon.env.example` | Yes (it's a template, holds no real secret) | Copy to `neon.env` and fill in your real `NEON_DATABASE_URL` |
| `neon.env` | No | `scripts/export-neon-dump.sh` (reads `NEON_DATABASE_URL`) |
| `neon_dump.sql` | No | Produced by `export-neon-dump.sh`, consumed by `scripts/restore-neon-dump.sh` |

## Setup

```bash
cp secrets/neon.env.example secrets/neon.env
# edit secrets/neon.env with your real Neon connection string
scripts/export-neon-dump.sh    # requires VPN disconnected (Neon DNS)
scripts/restore-neon-dump.sh   # loads the dump into the local Docker Postgres
```

## Rules

- Never hardcode `NEON_DATABASE_URL` (or any other secret) in committed code
  or scripts — always read it from `secrets/neon.env`.
- Treat `neon.env` as a live production/staging credential. If it ever
  leaks, rotate it in the Neon dashboard, don't just delete the local file.
- `neon_dump.sql` may contain real data (including anything PII-adjacent
  seeded in the target Neon branch) — never move it outside this gitignored
  folder.
