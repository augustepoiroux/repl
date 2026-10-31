# List of branches to rebase (space-separated, assumed stacked in order)
branches="fix-sorry-ctx incremental_processing auto-prefix-optimization declaration-extraction add-set-option"

# Check for command line arguments
if [ $# -ne 2 ]; then
  echo "Usage: $0 <old_base> <new_base>"
  exit 1
fi

# Old base (commit/branch/ref they diverge from)
old_base=$1

# New base (target to rebase onto)
new_base=$2

current_base=$new_base

for branch in $branches; do
  # Check if branch is already rebased (resumable)
  if git merge-base --is-ancestor $current_base $branch 2>/dev/null; then
    echo "Branch $branch is already rebased onto $current_base, skipping."
    old_base=$(git rev-parse $branch)
    current_base=$branch
    continue
  fi

  echo "Rebasing $branch onto $current_base..."
  old_branch_head=$(git rev-parse $branch)
  git checkout $branch
  git rebase --onto $current_base $old_base $branch
  if [ $? -ne 0 ]; then
    echo "Rebase failed for $branch. Resolve conflicts and run 'git rebase --continue', then rerun the script."
    break
  fi

  # Run tests after successful rebase
  echo "Building and testing REPL for $branch..."
  lake build
  echo '{"cmd": "#eval 1"}' | lake exe repl
  if [ $? -ne 0 ]; then
    echo "REPL check failed for $branch. Fix issues and rerun the script."
    break
  fi

  echo "Branch $branch rebased and tested successfully."
  old_base=$old_branch_head
  current_base=$branch
done
