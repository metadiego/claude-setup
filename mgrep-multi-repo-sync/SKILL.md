---
name: mgrep-multi-repo-sync
description: Reference for the mgrep nested-repo sync setup — a SessionStart hook plus mgrep-sync-all.sh that index every git repo under a parent directory, working around mgrep's git ls-files enumeration that skips nested repos.
---

# mgrep multi-repo sync

## Problem

mgrep enumerates files with `git ls-files`, which never descends into nested
git repositories. A parent directory that holds multiple repos (e.g.
`~/Documents/Dev/investing/` containing `lightweight-agent`, `market-mind`,
`TradingAgents`) therefore syncs **0 files**, and the mgrep Claude Code
plugin's background sync has the same blind spot.

Search is unaffected once files are in the store: mgrep filters results with a
`path starts_with <search path>` prefix, so a search run from the parent
directory matches everything synced from the subrepos.

## Fix

Two pieces, bundled in this folder:

- `mgrep-sync-all.sh` — syncs a directory itself (mgrep natively handles the
  single-repo and no-git cases) plus every nested git repo found under it
  (up to 5 levels deep, `node_modules` skipped), deduplicated. Refuses to run
  at or above `$HOME`, mirroring mgrep's own guard.
- `hook.json` — a Claude Code `SessionStart` hook that runs the script in the
  background for every session, so any directory — single repo, multi-repo
  parent, or plain folder — gets fully indexed.

`async: true` keeps it from blocking session startup; failures are swallowed
(`|| true`) so a Mixedbread outage never breaks a session.

## Install

1. Copy the script into place and make it executable:
   ```bash
   mkdir -p ~/.claude/scripts
   cp mgrep-sync-all.sh ~/.claude/scripts/
   chmod +x ~/.claude/scripts/mgrep-sync-all.sh
   ```
2. Merge the `hooks` block from `hook.json` into `~/.claude/settings.json`
   (top level). Don't replace an existing `hooks` key — merge the
   `SessionStart` entry into it.
3. Run `/hooks` once (or restart Claude Code) so settings reload.

Requires mgrep installed and logged in (`mgrep login`).

## Manual use

```bash
~/.claude/scripts/mgrep-sync-all.sh                # sync repos under $PWD
~/.claude/scripts/mgrep-sync-all.sh ~/some/parent  # sync repos under a path
mgrep search "how are trades executed" .           # then search from anywhere
```

## Troubleshooting

- Search returns nothing → run the script manually; check `mgrep login`.
- Hook not firing → run `/hooks` once (or restart) so settings reload; verify
  with `jq '.hooks' ~/.claude/settings.json`.
- Upstream context: the proper fix is nested-repo recursion in
  `NodeGit.getGitFiles` (mgrep `dist/lib/git.js`); if mixedbread-ai/mgrep
  ships that, this hook becomes redundant but harmless.
