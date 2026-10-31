#!/usr/bin/env bash
set -euo pipefail

# If not running from a temp copy, re-exec from /tmp so branch switches don't remove or alter the running script
if [[ "${SYNC_UPSTREAM_SELF_RUNNING:-0}" != "1" ]]; then
  tmp_script=$(mktemp /tmp/sync_upstream.XXXXXX.sh)
  cp "$0" "$tmp_script"
  chmod +x "$tmp_script"
  export SYNC_UPSTREAM_SELF_RUNNING=1
  trap 'rm -f "$tmp_script"' EXIT
  exec "$tmp_script" "$@"
fi

# sync_upstream.sh
# Automates synchronizing upstream leanprover-community/repl changes into the fork:
# 1. Rebases fork master on upstream/master.
# 2. Rebases the stacked feature branches on upstream/master.
# 3. Refreshes nightly (reset to top feature branch, merge master).
# 4. Runs full tests on nightly.
# 5. Optionally tags and pushes updated branches and tag.

UPSTREAM_URL="https://github.com/leanprover-community/repl.git"
DRY_RUN=false
FORCE=false
PUSH=false
SKIP_TESTS=false
export LEAN_NUM_THREADS=${LEAN_NUM_THREADS:-6}

FEATURE_BRANCHES=(
  "fix-sorry-ctx"
  "incremental_processing"
  "auto-prefix-optimization"
  "declaration-extraction"
  "add-set-option"
)

usage() {
  cat <<'USAGE'
Usage: ./sync_upstream.sh [options]

Options:
  --dry-run      Perform rebase and tests without pushing or creating persistent tags.
  --force        Bypass ancestor check and force running rebase/test pipeline.
  --push         Push rebased branches and created tag to origin upon test success.
  --skip-tests   Skip running 'lake exe test' (for fast testing/debugging only).
  -h, --help     Show this help message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --push)
      PUSH=true
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Ensure upstream remote exists and is configured
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "==> Adding upstream remote: $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

echo "==> Fetching upstream master and tags..."
git fetch upstream master --tags

# Extract latest upstream Lean toolchain
TOOLCHAIN=$(git show upstream/master:lean-toolchain | tr -d '[:space:]' | sed 's#^leanprover/lean4:##')
echo "==> Upstream master toolchain: $TOOLCHAIN"

# Extract active REPL version dynamically
REPL_VERSION=$(grep -E '^### v[0-9]+\.[0-9]+' README.md 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '[:space:]' || true)
if [[ -z "$REPL_VERSION" ]]; then
  REPL_VERSION=$(git tag -l 'v1.*_lean-toolchain-*' | sed -E 's/^(v1\.[^_]+)_.*/\1/' | sort -Vu | tail -n 1)
fi
echo "==> Active REPL version: $REPL_VERSION"

# Check if master is already up-to-date with upstream/master
FIRST_BRANCH="${FEATURE_BRANCHES[0]}"
UPSTREAM_HEAD=$(git rev-parse upstream/master)
OLD_UPSTREAM_BASE=$(git merge-base "$FIRST_BRANCH" upstream/master)

if [ "$FORCE" = false ]; then
  if git merge-base --is-ancestor upstream/master master 2>/dev/null; then
    if [ "$OLD_UPSTREAM_BASE" = "$UPSTREAM_HEAD" ]; then
      echo "==> Upstream master is already integrated into master and feature branches. Nothing to do."
      exit 0
    else
      echo "==> Master is up-to-date with upstream/master, but feature branches diverge from an older upstream base ($OLD_UPSTREAM_BASE)."
    fi
  fi
fi

# 1. Rebase master onto upstream/master
if ! git merge-base --is-ancestor upstream/master master 2>/dev/null; then
  echo "==> Rebasing master onto upstream/master..."
  git checkout master
  git rebase upstream/master
else
  echo "==> Master is already based on upstream/master."
fi

# 2. Rebase feature stack onto upstream/master
echo "==> Rebasing feature stack from $OLD_UPSTREAM_BASE onto $UPSTREAM_HEAD..."
current_base="$UPSTREAM_HEAD"
old_base="$OLD_UPSTREAM_BASE"

for branch in "${FEATURE_BRANCHES[@]}"; do
  if git merge-base --is-ancestor "$current_base" "$branch" 2>/dev/null; then
    echo "Branch $branch is already rebased onto $current_base, skipping."
    old_base=$(git rev-parse "$branch")
    current_base="$branch"
    continue
  fi

  echo "==> Rebasing $branch onto $current_base (old base: $old_base)..."
  old_branch_head=$(git rev-parse "$branch")
  git checkout "$branch"
  git rebase --onto "$current_base" "$old_base" "$branch"

  echo "==> Verifying REPL build for $branch..."
  lake build
  echo '{"cmd": "#eval 1"}' | lake exe repl >/dev/null

  old_base="$old_branch_head"
  current_base="$branch"
done

# 3. Refresh nightly
LAST_FEATURE_BRANCH="${FEATURE_BRANCHES[-1]}"
echo "==> Refreshing nightly from $LAST_FEATURE_BRANCH and merging master..."

if [ "$DRY_RUN" = false ] && git show-ref --verify --quiet refs/heads/nightly; then
  BACKUP_NIGHTLY="backup/nightly-before-$(date +%Y%m%d_%H%M%S)"
  echo "==> Creating backup branch: $BACKUP_NIGHTLY"
  git branch "$BACKUP_NIGHTLY" nightly
fi

git checkout nightly
git reset --hard "$LAST_FEATURE_BRANCH"
git merge master -m "Merge master into nightly ($TOOLCHAIN)"

# 4. Run tests on nightly
if [ "$SKIP_TESTS" = false ]; then
  echo "==> Running full tests on nightly with LEAN_NUM_THREADS=$LEAN_NUM_THREADS..."
  lake exe test
else
  echo "==> Skipping tests (--skip-tests specified)."
fi

# 5. Tag and Push
TAG_NAME="${REPL_VERSION}_lean-toolchain-${TOOLCHAIN}"

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "==> [DRY RUN SUCCESSFUL]"
  echo "    Would create tag: $TAG_NAME"
  echo "    Would push: master, ${FEATURE_BRANCHES[*]}, nightly"
  echo "    Would push tag: $TAG_NAME"
elif [ "$PUSH" = true ]; then
  echo "==> Creating tag $TAG_NAME..."
  if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "Tag $TAG_NAME already exists."
  else
    git tag -a "$TAG_NAME" -m "REPL $REPL_VERSION with Lean $TOOLCHAIN"
  fi

  echo "==> Pushing branches to origin..."
  git push --force-with-lease origin master
  git push --force-with-lease origin "${FEATURE_BRANCHES[@]}"
  git push --force-with-lease origin nightly
  git push origin "$TAG_NAME"
  echo "==> Upstream sync and push completed successfully for $TOOLCHAIN!"
else
  echo ""
  echo "==> Sync and tests completed successfully!"
  echo "    Run with --push to create tag $TAG_NAME and push all branches to origin."
fi
