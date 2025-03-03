#!/bin/bash

# Define the paths
IN_DIR="test"
EXPECTED_DIR="test"

lake build

# ignore locale to ensure test `bla` runs before `bla2`
export LC_COLLATE=C

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
    .lake/build/bin/repl < "$infile" > "$tmpfile" 2>&1

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

# Run the Mathlib tests - skipped as no Mathlib releases exist for v4.13.0-rc1
# cp lean-toolchain test/Mathlib/
# cd test/Mathlib/ && ./test.sh
