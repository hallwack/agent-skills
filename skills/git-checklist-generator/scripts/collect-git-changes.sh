#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash collect-git-changes.sh [options] [base-ref]

Collect committed changes between BASE and HEAD for a PR description.
Uncommitted changes are reported but excluded.
No network access or Git mutations are performed (no fetch).

Options:
  --with-diff[=N]   Also print the committed diff, truncated to N lines
                    (default 400). Off by default to keep output small.
  -h, --help        Show this help.

Base selection when base-ref is omitted:
  1. origin/HEAD (remote default branch)
  2. origin/main, origin/master
  3. Local main, master
  4. Current branch upstream, only if it is a different branch
USAGE
}

base=""
with_diff=0
diff_limit=400

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --with-diff) with_diff=1 ;;
    --with-diff=*)
      with_diff=1
      diff_limit="${arg#*=}"
      if ! [[ "$diff_limit" =~ ^[0-9]+$ ]]; then
        echo "Error: --with-diff expects a number of lines." >&2
        exit 1
      fi
      ;;
    -*) echo "Error: unknown option '$arg'." >&2; usage >&2; exit 1 ;;
    *)
      if [[ -n "$base" ]]; then
        echo "Error: only one base ref may be given." >&2
        exit 1
      fi
      base="$arg"
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: run this script from inside the target Git repository." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
branch="$(git branch --show-current)"
head_note=""

if [[ -z "$branch" ]]; then
  # Detached HEAD is normal in CI checkouts; continue with a warning.
  branch="(detached at $(git rev-parse --short HEAD))"
  head_note="detached HEAD"
fi

has_commit() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null 2>&1
}

base_source="argument"
if [[ -z "$base" ]]; then
  base_source="auto-detected"
  origin_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"

  for candidate in "$origin_head" origin/main origin/master main master; do
    [[ -z "$candidate" ]] && continue
    # Never use the current branch (or its own remote copy) as the base.
    [[ "$candidate" == "$branch" || "$candidate" == "origin/$branch" ]] && continue
    if has_commit "$candidate"; then
      base="$candidate"
      break
    fi
  done

  if [[ -z "$base" && -n "$upstream" && "${upstream#*/}" != "$branch" ]] && has_commit "$upstream"; then
    base="$upstream"
  fi

  if [[ -z "$base" ]]; then
    echo "Error: unable to determine a base ref. Pass one explicitly, e.g. 'develop'." >&2
    exit 1
  fi
fi

if ! has_commit "$base"; then
  echo "Error: base ref '$base' does not resolve." >&2
  exit 1
fi

if ! merge_base="$(git merge-base "$base" HEAD 2>/dev/null)"; then
  echo "Error: no common ancestor with '$base'." >&2
  exit 1
fi

commit_count="$(git rev-list --count --no-merges "${base}..HEAD")"
merge_count="$(git rev-list --count --merges "${base}..HEAD")"
working_tree_status="$(git status --short)"

printf '# Git change collection\n\n'
printf -- '- Repository: `%s`\n' "$repo_root"
printf -- '- Branch: `%s`\n' "$branch"
printf -- '- Base ref: `%s` (%s; local refs only, not fetched)\n' "$base" "$base_source"
printf -- '- Merge base: `%s`\n' "$(git rev-parse --short "$merge_base")"
printf -- '- Range: `%s...HEAD`\n' "$base"
printf -- '- Commit count: %s (excluding %s merge commits)\n' "$commit_count" "$merge_count"
[[ -n "$head_note" ]] && printf -- '- Warning: %s\n' "$head_note"

if [[ -n "$working_tree_status" ]]; then
  printf -- '- Working tree: uncommitted changes detected; excluded\n'
else
  printf -- '- Working tree: clean\n'
fi

if [[ "$commit_count" -eq 0 ]]; then
  printf '\nNo commits found between `%s` and `HEAD`.\n' "$base"
  exit 0
fi

if [[ "$commit_count" -gt 150 ]]; then
  printf -- '- Warning: %s commits is unusually large; the base ref may be wrong\n' "$commit_count"
fi

printf '\n## Commits (oldest first)\n\n'
# Subject plus body, so BREAKING CHANGE, bullets and "closes #N" survive.
git log --no-merges --reverse --date=short \
  --format='### `%h` %s%n_%an, %ad_%n%n%b%n' "${base}..HEAD"

printf '\n## Changed files (status)\n\n```\n'
git diff --name-status --find-renames "${base}...HEAD"
printf '```\n'

printf '\n## Changed files summary\n\n```\n'
git diff --stat --find-renames "${base}...HEAD" | tail -n 60 || true
printf '```\n'

printf '\n## Signals (path-based hints, verify before reporting)\n\n'
files="$(git diff --name-only --find-renames "${base}...HEAD")"
signal() {
  local label="$1" pattern="$2" hits
  hits="$(grep -Ei "$pattern" <<<"$files" || true)"
  if [[ -n "$hits" ]]; then
    printf -- '- %s:\n' "$label"
    sed 's/^/  - `/; s/$/`/' <<<"$hits" | head -n 15 || true
  fi
}
signal "Database migrations" '(^|/)(migrations?|db/migrate|schema)(/|\.)|\.sql$'
signal "Configuration / environment" '(^|/)\.env|config/|\.(ya?ml|toml|ini)$|settings\.'
signal "Dependencies" '(^|/)(package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|composer\.(json|lock)|go\.(mod|sum)|requirements.*\.txt|pyproject\.toml|poetry\.lock|Cargo\.(toml|lock)|Gemfile(\.lock)?|flake\.(nix|lock))$'
signal "Tests" '(^|/)(tests?|__tests__|spec)/|[._-](test|spec)\.|_test\.go$'
signal "Documentation" '\.(md|mdx|rst|adoc)$|(^|/)docs?/'
signal "CI / deployment" '(^|/)(\.github|\.gitlab-ci|\.circleci|deploy|k8s|helm|terraform)|Dockerfile|docker-compose|\.gitlab-ci\.yml$'

if [[ "$with_diff" -eq 1 ]]; then
  printf '\n## Committed diff (first %s lines)\n\n```diff\n' "$diff_limit"
  git diff --find-renames --no-ext-diff --unified=3 "${base}...HEAD" | head -n "$diff_limit" || true
  printf '```\n'
fi
