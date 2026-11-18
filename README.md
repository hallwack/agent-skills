# agent-skills

Agent skills (`SKILL.md`) installable with the [`skills`](https://github.com/vercel-labs/skills) CLI.

| Skill | Description |
|---|---|
| [`git-checklist-generator`](skills/git-checklist-generator/SKILL.md) | Generates a development checklist and a pull request description from the git commits on the current branch. Platform agnostic (plain `git`). Optionally polishes the summary with `humanizer`. |

```
skills/git-checklist-generator/
├── SKILL.md                         # workflow + output template
└── scripts/
    └── collect-git-changes.sh       # read-only change collector (no fetch, no mutations)
```

## Companion skills (installed separately)

| Skill | Source | Used for |
|---|---|---|
| `humanizer` | [`blader/humanizer`](https://github.com/blader/humanizer) | Polishing the PR **Summary** only. Checklist items, file paths and IDs are never rewritten. Optional: without it the skill still works. |

## Install

Run from the root of the repository where you want to use the skill:

```bash
# Project install (default) → e.g. ./.claude/skills/<name>
npx skills add hallwack/agent-skills --skill git-checklist-generator
npx skills add blader/humanizer                       # optional companion

# Global (all projects)
npx skills add hallwack/agent-skills --skill git-checklist-generator -g
npx skills add blader/humanizer -g

# Specific agents
npx skills add hallwack/agent-skills --skill git-checklist-generator -a claude-code -a cursor
```

Update later with `npx skills update`.

## Usage

On your feature branch (run `git fetch` first if the base may be stale), ask your agent:

- "Buatkan deskripsi PR dari commit branch ini"
- "PR description against `develop`"
- "Checklist saja, tanpa humanizer"
- "Simpan ke PR_DESCRIPTION.md"

Or run the collector yourself:

```bash
bash .claude/skills/git-checklist-generator/scripts/collect-git-changes.sh            # auto base
bash .claude/skills/git-checklist-generator/scripts/collect-git-changes.sh develop    # explicit base
bash .claude/skills/git-checklist-generator/scripts/collect-git-changes.sh --with-diff=300
```

Requirements: `git`, `bash`, and an agent with shell access.
