---
name: continuous-learning
description: Use when setting up automatic learning from Claude Code sessions, when the user wants patterns (error fixes, workarounds, debugging techniques, corrections) extracted and remembered across sessions, when configuring a Stop hook for session evaluation, or when reviewing/curating learned skills in ~/.claude/skills/learned/.
origin: ECC
---

# Continuous Learning Skill

Automatically evaluates Claude Code sessions when they end and extracts reusable patterns as learned skills in `~/.claude/skills/learned/`, so future sessions benefit from past corrections, fixes, and workarounds.

## When to Activate

- Setting up automatic pattern extraction from Claude Code sessions
- Configuring the Stop hook for session evaluation
- A Stop hook just prompted you to extract patterns from this session
- Reviewing or curating learned skills in `~/.claude/skills/learned/`
- Adjusting extraction thresholds or pattern categories

## How It Works

`evaluate-session.sh` runs as a **Stop hook** each time Claude finishes responding:

1. **Loop guard** — exits immediately if `stop_hook_active` is true (prevents infinite stop loops)
2. **Once per session** — exits if this session was already evaluated (marker file in `/tmp`)
3. **Session gate** — reads `transcript_path` from the hook's stdin JSON and counts user messages; skips sessions below `min_session_length` (default: 10)
4. **Extraction prompt** — emits `{"decision": "block", "reason": ...}` on stdout, which makes Claude run one extraction pass before stopping

The critical detail most setups get wrong: the Stop hook payload does **not** contain the transcript — it contains `transcript_path` (a JSONL file), `session_id`, and `stop_hook_active`. Do not spawn a nested `claude` invocation from the hook; let the hook's block-reason instruct the already-running Claude instead.

## Hook Setup

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/skills/continuous-learning/evaluate-session.sh"
      }]
    }]
  }
}
```

Make the script executable: `chmod +x ~/.claude/skills/continuous-learning/evaluate-session.sh`

## Extraction Workflow (what Claude does when invoked)

Whether triggered manually (`/continuous-learning`) or by the hook:

1. Review the session for candidate patterns worth keeping (see Pattern Types below)
2. **Propose, don't write.** Present the candidates to the user as a short list — proposed skill name, category, and a one-line gist of what it captures — and ask which to store (use AskUserQuestion with multiSelect when available). If no candidates qualify, say so and stop.
3. Only after the user approves, write each selected pattern to `~/.claude/skills/learned/<skill-name>/SKILL.md`:

```markdown
---
name: <kebab-case-name>
description: Use when <specific triggering conditions and symptoms>
metadata:
  category: error_resolution | user_corrections | workarounds | debugging_techniques | project_specific
  learned: <YYYY-MM-DD>
---

# <Title>

## Pattern
<the reusable technique, 2-15 lines, concrete and actionable>

## Evidence
<what happened in the session that proved this works>
```

4. Before proposing, check `~/.claude/skills/learned/` for an existing skill covering the same pattern; offer an update to it instead of a duplicate

Zero candidates is the normal case — most sessions produce nothing worth keeping.

The frontmatter is required — files without `name` and `description` are never discovered by future sessions. Descriptions must start with "Use when..." and state triggering conditions, not summarize the pattern.

## Pattern Types

| Extract | Description |
|---------|-------------|
| `error_resolution` | How a specific error was diagnosed and fixed |
| `user_corrections` | The user corrected Claude's approach — capture the preferred way |
| `workarounds` | Solutions to framework/library/tool quirks |
| `debugging_techniques` | Effective debugging approaches that worked |
| `project_specific` | Project conventions not written down anywhere |

| Ignore | Why |
|--------|-----|
| `simple_typos` | Not reusable |
| `one_time_fixes` | Won't recur |
| `external_api_issues` | Outage/flakiness, not a pattern |

## Configuration

Edit `config.json` in this skill's directory:

```json
{
  "min_session_length": 10,
  "prompt_extraction": true,
  "learned_skills_path": "~/.claude/skills/learned/"
}
```

- `min_session_length` — minimum user messages before evaluation triggers
- `prompt_extraction` — `true` emits the block-prompt (reliable); `false` only logs to stderr (original ECC v1 behavior, fires rarely)
- `learned_skills_path` — where learned skills are written

## Curation

Learned skills accumulate — review them periodically:

- Delete skills that turned out wrong or never triggered
- Merge near-duplicates
- Promote battle-tested ones into real skills in your skills repo (with proper testing)

## Why Stop Hook?

- **Lightweight** — gating logic runs in milliseconds; no latency added to messages
- **Complete context** — the session is finished, so all patterns are visible
- **One extraction pass** — marker file + `stop_hook_active` guard ensure it runs at most once per session

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Parsing `.transcript` from hook stdin | Payload has `transcript_path` (JSONL file path), not inline transcript |
| Spawning `claude --print` inside the hook | Use `decision: block` to make the running Claude do the extraction |
| Ignoring `stop_hook_active` | Causes infinite stop-hook loops |
| Learned files without frontmatter | Never discovered; always include `name` + "Use when..." `description` |
| Extracting something from every session | Most sessions have nothing worth keeping; zero extractions is the normal case |
| Writing learned skills without approval | Always propose candidates first — the user decides which are worth storing |

## Related

- `strategic-compact` skill — write learnings before compacting; this skill captures them at session end
- ECC `continuous-learning-v2` — instinct-based successor with confidence scoring and project scoping, if this outgrows its usefulness
- [The Longform Guide](https://x.com/affaanmustafa/status/2014040193557471352) — section on continuous learning
