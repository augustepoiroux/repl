#!/bin/bash

set -e  # Exit on error

# Check that we have the repository and branch name
if [ $# -lt 2 ]; then
  echo "Usage: $0 <remote-name> <branch-name> [base-branch]"
  echo "Example: $0 origin feature-branch"
  echo "Example with base branch: $0 origin feature-branch main"
  exit 1
fi

REMOTE="$1"
BRANCH="$2"
BASE_BRANCH="$3"

# For a local-only branch, get all commits since it diverged from the base branch
if ! git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" &>/dev/null; then
  echo "Branch $BRANCH doesn't exist on remote $REMOTE yet."
  echo "Will push all commits since diverging from $BASE_BRANCH."

  # Find divergence point with base branch
  MERGE_BASE=$(git merge-base "$BRANCH" "$REMOTE/$BASE_BRANCH" 2>/dev/null || git merge-base "$BRANCH" "$BASE_BRANCH")

  if [ -z "$MERGE_BASE" ]; then
    echo "Could not find common ancestor with $BASE_BRANCH. Using all commits in the branch."
    COMMITS=$(git rev-list --reverse "$BRANCH")
  else
    COMMITS=$(git rev-list --reverse "$MERGE_BASE..$BRANCH")
  fi
else
  echo "Branch $BRANCH exists on remote. Getting only new commits."
  COMMITS=$(git rev-list --reverse "$REMOTE/$BRANCH..$BRANCH")
fi

# Check if there are any commits to push
if [ -z "$COMMITS" ]; then
  echo "No commits to push in the specified branch."
  exit 0
fi

# Count commits to push
COMMIT_COUNT=$(echo "$COMMITS" | wc -l)
echo "Found $COMMIT_COUNT commits to push one by one."

# Ask for confirmation
read -p "Do you want to continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Push each commit individually
COUNTER=1
PREVIOUS_COMMIT=""

for COMMIT in $COMMITS; do
  COMMIT_MSG=$(git log --format=%B -n 1 $COMMIT | head -n 1)
  echo "[$COUNTER/$COMMIT_COUNT] Pushing commit $COMMIT: $COMMIT_MSG"

  # For the first push to a new branch, we need to set up tracking
  if [ $COUNTER -eq 1 ] && ! git ls-remote --exit-code --heads "$REMOTE" "$BRANCH" &>/dev/null; then
    echo "Creating new remote branch $BRANCH with first commit..."
    git push -u "$REMOTE" "$COMMIT:refs/heads/$BRANCH" || {
      echo "Error pushing first commit $COMMIT. Aborting."
      exit 1
    }
  else
    # For subsequent commits, push to the existing branch
    git push "$REMOTE" "$COMMIT:refs/heads/$BRANCH" || {
      echo "Error pushing commit $COMMIT. Aborting."
      exit 1
    }
  fi

  # Wait a few seconds to allow CI to kick off
  echo "Waiting 3 seconds before pushing the next commit..."
  sleep 3

  COUNTER=$((COUNTER+1))
  PREVIOUS_COMMIT="$COMMIT"
done

echo "All commits pushed successfully!"
echo "Setting up tracking branch relationship..."
git branch --set-upstream-to="$REMOTE/$BRANCH" "$BRANCH"
echo "Done! Your local branch is now tracking the remote branch."
