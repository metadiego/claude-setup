---
name: save-session
description: Use when the user wants to save or wrap up the current session — runs on /save-session to write a summary of the conversation so far into .claude/sessions/, preserving what was done, decided, and left unfinished so a fresh session can pick up. Often used before the user clears context.
---

# save-session

## Overview

Capture a durable summary of the current session to `.claude/sessions/`, then hand control back to the user to clear context. The summary is a handoff note: enough that a fresh session (or a future you) can pick up where this one left off.

**Key constraint:** A skill cannot run `/clear` — that is a built-in Claude Code command only the user can invoke. This skill writes the file, then tells the user to type `/clear`.

## Steps

1. **Determine the target directory.** Use `.claude/sessions/` relative to the current working directory (the project root). Create it if it does not exist.

2. **Build a timestamped filename.** Get the timestamp via `date "+%Y-%m-%d_%H%M%S"`. Filename: `<timestamp>-<short-slug>.md`, where the slug is 2-4 kebab-case words describing the session's main topic (e.g. `2026-06-08_142530-auth-refactor.md`).

3. **Write the summary** to that file using the template below. Base it on the actual conversation — do not invent work that did not happen. If something was left incomplete or undecided, say so explicitly; that is the most valuable part of a handoff.

4. **Confirm and instruct.** Tell the user the file path that was written, then instruct them: **"Run `/clear` to reset the context."** Do not claim the context was cleared — you cannot do that.

## Summary Template

```markdown
# Session Summary — <date> <time>

## Topic
One-line description of what this session was about.

## What was done
- Concrete changes, files touched, commands run, decisions made.

## Key decisions & rationale
- Decision → why. Include rejected alternatives if relevant.

## Open / unfinished
- What is incomplete, broken, or still pending. Be specific.

## Next steps
- The first thing a fresh session should pick up.

## Useful references
- Relevant file paths, commands, links, PR/issue numbers.
```

## Common Mistakes

- **Claiming the context was cleared.** You can't. Always end by instructing the user to run `/clear`.
- **Inventing accomplishments.** Summarize only what actually happened this session.
- **Omitting unfinished work.** The handoff value is highest for what's still open — never drop it.
- **Writing to the wrong place.** Always project-level `.claude/sessions/`, not `docs/` or a global dir.
