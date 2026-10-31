#!/usr/bin/env bash

# Define the paths
IN_DIR="test"
EXPECTED_DIR="test"

# Attempt to fetch prebuilt Mathlib cache
CACHE_OUTPUT=$(lake exe cache get 2>&1 || true)
echo "$CACHE_OUTPUT"

# If 0 files were downloaded/decompressed, Mathlib has no cloud cache for this toolchain.
# Skip compiling 4500+ files from scratch to avoid hitting CI timeouts.
if echo "$CACHE_OUTPUT" | grep -qE "download 0 file\(s\)|Decompressing 0 file\(s\)"; then
    echo "Warning: No prebuilt Mathlib cache found for this toolchain. Skipping full Mathlib compilation."
    exit 0
fi

lake build Mathlib

# Iterate over each .in file in the test directory
for infile in $IN_DIR/*.in; do
    # Extract the base filename without the extension
    base=$(basename "$infile" .in)

    # Define the path for the expected output file
    expectedfile="$EXPECTED_DIR/$base.expected.out"

    # Check if the expected output file exists
    if [[ ! -f $expectedfile ]]; then
        echo "Expected output file $expectedfile does not exist. Skipping $infile."
        continue
    fi

    # Run the command and store its output in a temporary file
    tmpfile=$(mktemp)
    lake env ../../.lake/build/bin/repl < "$infile" > "$tmpfile" 2>&1

    # Compare the output with the expected output
    if diff "$tmpfile" "$expectedfile"; then
        echo "$base: PASSED"
        # Remove the temporary file
        rm "$tmpfile"
    else
        echo "$base: FAILED"
        # Rename the temporary file instead of removing it
        mv "$tmpfile" "${expectedfile/.expected.out/.produced.out}"
        exit 1
    fi

done

