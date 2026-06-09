---
name: start-feature-worktree
description: Use when you are one of several agents working in the same repo and need an isolated worktree for a new feature, based on the latest shared integration branch (e.g. origin/dev). Creates a fresh worktree + feature branch off the fetched integration base without disturbing other agents' worktrees, branches, or uncommitted work. Runs on /start-feature-worktree <feature description>.
---

# start-feature-worktree

## Overview

Carve out an isolated worktree for a new feature, based on the latest state of a shared integration branch (default `origin/dev`), so that multiple agents can work in the same repo at the same time without colliding.

**Core principle:** Each agent gets its own worktree and its own `feat/<slug>` branch, branched from a freshly fetched integration base. The skill only ever *adds* state (objects, one ref, one worktree). It never modifies another agent's worktree, branch, or working files.

**Invocation:** `/start-feature-worktree <feature description>` — e.g. `/start-feature-worktree login form`

**Announce at start:** "Using start-feature-worktree to set up an isolated worktree for `<feature>`."

## When to Use

- Several agents are working in adjacent sessions on the same repository.
- You need to start a *new, distinct* feature isolated from the main checkout and from other agents.
- The team coordinates through a shared remote integration branch (e.g. `dev`).

**When NOT to use:**
- You're collaborating on an existing feature branch someone else owns (just check it out).
- There's no shared integration branch and no remote (this skill will tell you and ask).
- You only need generic worktree isolation with no shared-base semantics — use `superpowers:using-git-worktrees`.

## Quick Reference

| Step | Action | Command (sketch) |
|------|--------|------------------|
| 1 | Locate the main checkout | `git worktree list --porcelain` → first entry |
| 2 | Resolve integration base | try `origin/dev`, else ask |
| 3 | Fetch — **narrow only** | `git fetch origin dev` |
| 4 | Derive names | `feat/<slug>` + `.worktrees/<slug>` |
| 5 | Collision check | branch and dir must not already exist |
| 6 | Create worktree off base | `git worktree add … -b feat/<slug> origin/dev` |
| 7 | Switch + setup | work from the new worktree; install deps if needed |
| 8 | Report, stay local | no push |

## Steps

### 1. Locate the main checkout (handles "already in a worktree")

The first entry of `git worktree list --porcelain` is always the main working tree:

```bash
MAIN_TREE=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
```

Run all subsequent git operations against `MAIN_TREE` (e.g. `git -C "$MAIN_TREE" …`). This works whether you are currently in the main checkout or already inside another linked worktree — git worktrees cannot be nested, so we always create the new one from the main checkout.

If you were already inside a different worktree, report it and continue:
> "Currently in worktree `<A>`; basing the new feature worktree on the main checkout's `origin/dev` instead. Your work in `<A>` is left untouched."

**Do NOT** carry over uncommitted changes from the current worktree, and **do NOT** change what the main checkout has checked out.

### 2. Resolve the integration base (convention + fallback)

```bash
git -C "$MAIN_TREE" rev-parse --verify origin/dev   # convention
```

- If `origin/dev` resolves → use `remote=origin`, `branch=dev`.
- If it doesn't resolve, disambiguate why before prompting:

```bash
git -C "$MAIN_TREE" remote   # empty → no-remote case; non-empty → missing/wrong branch case
```

- **No remote at all** (output empty) → stop and report, then ask whether to base off a local branch instead:
  > "No remote is configured. Base the new feature worktree off a local branch instead? Which one?"
- **Remote exists but `origin/dev` is missing** → **ask once:**
  > "Which remote/branch is the integration base?"

Never silently invent a base.

### 3. Fetch the integration branch — NARROW ONLY

```bash
git -C "$MAIN_TREE" fetch origin dev
```

**Critical:** fetch the specific branch only. **Never** `git fetch --all`, and **never** `--prune`. A blind prune would delete `origin/<other-feature>` remote-tracking refs that adjacent agents rely on. A narrow fetch only adds objects and advances the shared `refs/remotes/origin/dev` pointer — it cannot touch any other worktree's branch or files.

If the fetch fails on a transient lock (another agent's git holds `packed-refs.lock`/`index.lock`), wait briefly and retry once or twice. Never `--force` past a lock.

### 4. Derive names

Slug = kebab-case of the feature description. Use this command so every agent produces the same slug (collapses runs of punctuation/space into one `-`, trims leading/trailing dashes):

```bash
SLUG=$(printf '%s' "$DESC" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
```

- `login form` → `login-form`; `fix   double  space` → `fix-double-space`
- Branch: `feat/<slug>` → `feat/login-form`
- Worktree dir: `<MAIN_TREE>/.worktrees/<slug>` (honor an existing `.worktrees/` or `worktrees/` convention if the repo already has one; `.worktrees` wins).

If the slug comes out empty (description was all punctuation), stop and ask for a usable feature name.

### 5. Collision check

```bash
git -C "$MAIN_TREE" rev-parse --verify "refs/heads/feat/<slug>" 2>/dev/null   # must FAIL (no output, non-zero)
test -e "<MAIN_TREE>/.worktrees/<slug>"                                       # must NOT exist
```

If either already exists, **stop and report** — another agent may own that feature. Do not reuse or overwrite.

### 6. Create the worktree + branch off the fetched base

```bash
git -C "$MAIN_TREE" worktree add "<MAIN_TREE>/.worktrees/<slug>" -b "feat/<slug>" origin/dev
```

The new branch is rooted at the freshly fetched `origin/dev`, regardless of which worktree you started in.

### 7. Switch and set up

Work from `<MAIN_TREE>/.worktrees/<slug>` for the rest of the session (use absolute paths or `git -C`). Run project setup if needed (install deps, copy env files following repo conventions).

### 8. Report — stay local

Report the worktree path, branch name, and base commit. **Do not push.** Publishing happens later at finish time — see `superpowers:finishing-a-development-branch`.

## Concurrency Safety — Why This Doesn't Disturb Other Agents

All worktrees share one object store and one ref database; each has its own working dir, index, and HEAD. This skill's writes are all additive or advance a shared pointer:

- **Fetch** adds objects and moves the shared `origin/dev` pointer forward. Other agents' local branches and files are untouched — they only integrate when *they* choose to `rebase`/`merge`. There is only one shared `origin/dev`; no worktree holds a private copy to overwrite.
- **New branch + new worktree** are additive refs/entries; the collision check prevents reusing a name another agent owns.

## Common Mistakes

- **`git fetch --all --prune`** — deletes other agents' remote-tracking refs. Always fetch the one integration branch.
- **Nesting a worktree** — creating from inside another worktree without resolving `MAIN_TREE` first. Always operate against the main checkout.
- **Changing the main checkout's HEAD** — branch off `origin/dev` directly; never `checkout dev` in the main tree.
- **Operating inside another agent's worktree** — never `reset`/`clean`/`checkout` anything you didn't create.
- **`--force` past a lock** — transient lock contention means wait and retry, not force.
- **Inventing a base** when `origin/dev` is missing — ask instead.
- **Pushing** — out of scope; stay local.
