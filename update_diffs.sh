#!/usr/bin/env bash

set -e

# Function to clean up temporary worktree on exit
cleanup() {
  if [ -d "$TEMP_WORKTREE_DIR" ]; then
    echo "Removing temporary worktree..."
    git worktree remove "$TEMP_WORKTREE_DIR" --force
    rm -rf "$TEMP_WORKTREE_DIR"
  fi
}
trap cleanup EXIT

# Check for correct number of arguments
if [ $# -ne 2 ]; then
  echo "Usage: $0 <commit-hash-1> <commit-hash-2>"
  exit 1
fi

COMMIT1="$1"
COMMIT2="$2"
VERSIONS_DIR="versions"

# Verify that the commits exist
if ! git cat-file -e "${COMMIT1}^{commit}" 2>/dev/null; then
  echo "Error: Commit '$COMMIT1' does not exist."
  exit 1
fi

if ! git cat-file -e "${COMMIT2}^{commit}" 2>/dev/null; then
  echo "Error: Commit '$COMMIT2' does not exist."
  exit 1
fi

# Check if the versions directory exists
if [ ! -d "$VERSIONS_DIR" ]; then
  echo "Error: Directory '$VERSIONS_DIR' does not exist."
  exit 1
fi

# Generate the diff between commit1 and commit2
echo "Generating new diff between $COMMIT1 and $COMMIT2..."
git diff "$COMMIT1" "$COMMIT2" > new_diff.diff

# Create a temporary worktree at commit1
TEMP_WORKTREE_DIR=$(mktemp -d)
OLDPWD=$(pwd)
echo "Creating temporary worktree at $TEMP_WORKTREE_DIR..."
git worktree add --detach "$TEMP_WORKTREE_DIR" "$COMMIT1"

# Iterate over all .diff files in the versions directory
for diff_file in "$VERSIONS_DIR"/*.diff; do
  if [ -f "$diff_file" ]; then
    echo "====================================="
    echo "Processing $diff_file..."

    # Apply the new_diff to the temporary worktree
    if patch -s -p1 -d "$TEMP_WORKTREE_DIR" < new_diff.diff; then
      echo "Applied new_diff.diff to temporary worktree successfully."
    else
      echo "Failed to apply new_diff.diff to $diff_file. Skipping this file."
      continue
    fi

    # Apply the existing diff file
    if patch -s -p1 -d "$TEMP_WORKTREE_DIR" < "$diff_file"; then
      echo "Applied $diff_file to temporary worktree successfully."
    else
      echo "Failed to apply $diff_file to temporary worktree. Skipping this file."
      continue
    fi

    # Navigate to the temporary worktree
    pushd "$TEMP_WORKTREE_DIR" > /dev/null

    # Generate the merged diff, including untracked files
    git add -A
    git diff --cached "$COMMIT1" > "$OLDPWD/merged_diff.diff"

    # Reset changes in the worktree
    git -C "$TEMP_WORKTREE_DIR" reset --hard "$COMMIT1"
    git -C "$TEMP_WORKTREE_DIR" clean -fd

    # Check if the merged_diff.diff can be applied cleanly to commit1
    # Do this check while still in the worktree
    if git apply --check "$OLDPWD/merged_diff.diff"; then
        # Copy the diff file to the original location (using full paths)
        mv "$OLDPWD/merged_diff.diff" "$OLDPWD/$diff_file"
        popd > /dev/null
        echo "Successfully updated $diff_file with the merged diff."
    else
        popd > /dev/null
        echo "Conflict detected when updating $diff_file. Skipping this file."
        rm "$TEMP_WORKTREE_DIR/merged_diff.diff"
    fi
  fi
done

# Clean up the temporary worktree
cleanup

# Clean up the temporary new_diff.diff file
rm new_diff.diff

# Detect tags between commit1 and commit2
TAGS=$(git log --oneline --decorate $COMMIT2..$COMMIT1 | grep 'tag:' | sed -n 's/.*tag: \([^,)]*\).*/\1/p')

for tag in $TAGS; do
  echo "====================================="
  echo "Generating diff for tag $tag..."
  git diff "$COMMIT1" "$tag" > "$VERSIONS_DIR/${tag}.diff"
  echo "Created $VERSIONS_DIR/${tag}.diff"
done

echo "All diff files have been processed."
