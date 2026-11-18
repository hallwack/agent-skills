---
name: git-checklist-generator
description: Generate a development checklist and a pull request description (title, summary, changes, testing, notes) from the git commits on the current branch, optionally polishing the summary with the humanizer skill. Use when drafting a PR/MR description from commit history.
---

# Git Checklist Generator

Turns the commits on the current branch into two markdown blocks:

- **A. Development Checklist**: everything done on the branch, grouped by type.
- **B. Pull Request Description**: a ready-to-paste PR/MR body with a suggested title.

This skill is **platform agnostic**. It uses only local `git` through the bundled script, so it works the same on GitHub, GitLab, Bitbucket, Gitea, Azure DevOps, or with no remote. Never call `gh`, `glab` or any platform API, and never push, fetch, or open/edit a PR unless the user explicitly asks.

## Inputs (ask only if unclear; otherwise use defaults)

| Input | Default |
|---|---|
| `base` | auto-detected by the script (`origin/HEAD` → `origin/main` → `origin/master` → `main` → `master`) |
| `sections` | both A and B. Produce only A or only B when the user asks for "checklist only" / "PR description only" |
| `language` | the language of the user's request (e.g. Indonesian or English). Keep identifiers, scopes, file paths and ticket IDs verbatim |
| `output` | print in the reply. If the user asks for a file, write `PR_DESCRIPTION.md` and do not commit it |
| `humanize` | `true` when a `humanizer` skill is available (see Step 5). `false` when the user says "no humanizer" / "tanpa humanizer" / `--raw` |

If the user pastes commit messages instead of pointing at a repo, skip Step 1 and work from the pasted text. Then Notes may only use what the text states.

## Workflow

### Step 1: Collect changes with the bundled script

The script lives next to this file. Run it from the target repository (the user's working directory), not from the skill folder:

```bash
bash <skill-dir>/scripts/collect-git-changes.sh [base-ref]
```

`<skill-dir>` is the directory containing this SKILL.md (for example `.claude/skills/git-checklist-generator` or `~/.claude/skills/git-checklist-generator`).

The script prints: repository, branch, base, range, commit count, working-tree status, every commit (subject + body, oldest first), `--name-status`, `--stat`, and **Signals** (path-based hints for migrations, config, dependencies, tests, docs, CI).

- Exit code ≠ 0: show the script's error and ask for a base ref (e.g. `develop`). Do not guess.
- Commit count 0: tell the user there is nothing between base and `HEAD`, and stop.
- Warning about > 150 commits: confirm the base with the user before continuing.
- Add `--with-diff[=N]` **only** when a commit message is too vague to describe and the user agrees. The diff clarifies wording; it is never a source of new items.

If the script cannot run (no bash, e.g. plain Windows shell), run these equivalents:

```bash
git log --no-merges --reverse --date=short --format='### `%h` %s%n%b%n' <base>..HEAD
git diff --name-status --find-renames <base>...HEAD
git diff --stat --find-renames <base>...HEAD
```

### Step 2: Parse and normalize commits

For each commit:

1. **Classify** with Conventional Commits (`type(scope)!: description`). For non-conventional subjects, classify by keyword: `add/implement/create/tambah` → feat; `fix/resolve/perbaiki/bug` → fix; `refactor/cleanup/rename/improve/perf` → refactor; `test` → test; `doc/readme/config/env/ci/build/deps/bump` → docs & config. If nothing matches, use the closest group and keep the wording.
2. **Breaking**: the type has `!`, or the body contains `BREAKING CHANGE:` / `BREAKING-CHANGE:`.
3. **Body bullets** (`-`, `*`, `•`) become sub-items of that commit's item.
4. **Drop trailers**: `Signed-off-by`, `Co-authored-by`, `Change-Id`, `Reviewed-by` and other `Key: value` trailers. Keep `closes/fixes/refs #N` and ticket IDs as references.
5. **Fold** `fixup!`, `squash!` and `amend!` commits into their target. Drop a commit and its later revert as a pair.
6. **Skip** low-signal commits (`wip`, `tmp`, `typo`, `format`, `lint`, a bare `update`) unless they are the only evidence of a change.
7. **Merge** near-duplicate items (same scope, same meaning) into one.

### Step 3: Map to the template sections

**A. Development Checklist** groups:

| Heading | Types |
|---|---|
| Features | feat |
| Bug Fixes | fix |
| Refactoring & Improvements | refactor, perf, style |
| Tests | test |
| Documentation & Configuration | docs, build, ci, chore, config/env/deps changes |

**B. Pull Request Description**:

- **Suggested title**: one line, Conventional Commits style when the repo uses it (`feat(auth): add refresh-token rotation`). Otherwise use a plain imperative sentence. Maximum about 72 characters.
- **Summary**: 1–3 sentences on purpose and outcome, derived only from the commits.
- **Changes**: 3–8 items, the reviewer-level view. Merge related A items; do not copy A line by line.
- **Testing**:
  - *Automated tests*: `- [x]` only for tests that commits or Signals → Tests show were added or changed. If there are none, omit this sub-block.
  - *Manual verification*: `- [ ]` items for user-visible features/fixes the reviewer should check. Use `- [x]` only if a commit or the user explicitly says it was verified.
- **Notes**: fill each line only from evidence:
  - *Breaking changes*: from `!` / `BREAKING CHANGE:` commits.
  - *Database migrations*: from Signals → Database migrations (list the files).
  - *Configuration*: from Signals → Configuration / environment, or commits about env/config.
  - *Deployment considerations*: from Signals → CI / deployment or Dependencies, or explicit commit text.
  - Omit a line with no evidence. Omit **Notes** entirely when every line is empty.

### Step 4: Fill the output template

Use this structure exactly. Translate headings only when the user writes in another language and asks for it; otherwise keep them as below.

```markdown
## A. Development Checklist

### Features
- [x] **scope**: Description (#ref)
  - [x] Sub-item from commit body

### Bug Fixes
- [x] ...

### Refactoring & Improvements
- [x] ...

### Tests
- [x] Add or update ...

### Documentation & Configuration
- [x] ...

---

## B. Pull Request Description

**Suggested title:** ...

### Summary

...

### Changes

- [x] ...

### Testing

**Automated tests**
- [x] Added or updated ...

**Manual verification**
- [ ] Verify ...

### Notes

- Breaking changes: ...
- Database migrations: ...
- Configuration: ...
- Deployment considerations: ...
```

### Step 5: Polish prose with `humanizer` (optional)

Companion skill: `humanizer` (recommended source: `blader/humanizer`). It is a separate skill and is not bundled here.

1. **Check availability.** Use it only if a skill named `humanizer` is installed or listed in this environment. If it is missing, or `humanize = false`, skip this step silently. Do not install it yourself, and do not imitate it from memory.
2. **Scope: prose only.** Pass through `humanizer` only:
   - B → **Summary**
   - B → **Suggested title**, only if it reads awkwardly
3. **Never pass these through it.** They stay exactly as generated:
   - every checklist line (`- [x]` / `- [ ]`) in A and B
   - Changes, Testing and Notes
   - code, identifiers, scopes, file paths, commit hashes, ticket IDs, Conventional Commit prefixes
4. **Tell it the register.** The text is a technical PR description: plain, neutral and concise. The language stays the same (Indonesian stays Indonesian). Do not add opinions, anecdotes, personality or new claims.
5. **Fact check after polishing.** Compare the polished Summary with the original. If the rewrite added, removed, generalized or softened any fact, such as a feature, a fix, a scope, a breaking change or a number, keep the original sentence.
6. Swap only the polished Summary/title back into the template. Nothing else changes.

### Step 6: Deliver

- Print the result in one fenced ```` ```markdown ```` block so it copies cleanly. If only B is requested, print only B.
- After the block, add at most two short lines: the base ref used (and that it was not fetched, so `git fetch` first if it may be stale), and anything uncertain, such as vague commits kept verbatim or uncommitted changes that were excluded. If `humanizer` was used, say so in a few words. If it was requested but not installed, say that and give the install command `npx skills add blader/humanizer`.

## Rules

- **Omit sections that do not apply.** No empty headings and no "N/A".
- **Never fill gaps with assumptions.** Every item must trace back to a commit, the user's words, or a script Signal. Signals are path-based hints: describe them as file facts ("adds `database/migrations/001_tokens.sql`"), not as behavior you did not see.
- Done work is `- [x]`. Work for the reviewer is `- [ ]`.
- One line per item; use sub-items for detail. Keep A at about 25 top-level items or fewer by merging related ones.
- Keep code, identifiers, paths and ticket IDs in backticks or verbatim. Do not convert references to platform URLs.
- Uncommitted changes are excluded. Mention them, but never list them as changes.
