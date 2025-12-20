#!/bin/bash

# Script to benchmark pickle/unpickle performance with Mathlib import

echo "=== Pickle/Unpickle Performance Benchmark ==="
echo ""

# Test 1: Baseline - Import Mathlib from scratch
echo "Test 1: Importing Mathlib from scratch (baseline)"
time_baseline=$(mktemp)
/usr/bin/time -f "%e" bash -c 'echo "{\"cmd\": \"import Mathlib\"}" | .lake/build/bin/repl > /dev/null 2>&1' 2> $time_baseline
baseline=$(cat $time_baseline)
echo "Time: ${baseline}s"
rm $time_baseline
echo ""

# Test 2: Create pickle with Mathlib
echo "Test 2: Creating pickle file with Mathlib import"
time_pickle=$(mktemp)
/usr/bin/time -f "%e" bash -c 'echo -e "{\"cmd\": \"import Mathlib\"}\n\n{\"cmd\": \"def testFunc := 42\", \"env\": 0}\n\n{\"pickleTo\": \"/tmp/mathlib_pickle.olean\", \"env\": 1}" | .lake/build/bin/repl > /dev/null 2>&1' 2> $time_pickle
pickle_time=$(cat $time_pickle)
echo "Time: ${pickle_time}s"
rm $time_pickle
echo ""

# Test 3: Unpickle Mathlib
echo "Test 3: Unpickling Mathlib from pickle file"
time_unpickle=$(mktemp)
/usr/bin/time -f "%e" bash -c 'echo "{\"unpickleEnvFrom\": \"/tmp/mathlib_pickle.olean\"}" | .lake/build/bin/repl > /dev/null 2>&1' 2> $time_unpickle
unpickle_time=$(cat $time_unpickle)
echo "Time: ${unpickle_time}s"
rm $time_unpickle
echo ""

# Calculate speedup
echo "=== Results ==="
echo "Baseline (import from scratch): ${baseline}s"
echo "Unpickle time: ${unpickle_time}s"
speedup=$(echo "scale=2; $baseline / $unpickle_time" | bc)
echo "Speedup: ${speedup}x"
echo ""

# Cleanup
rm -f /tmp/mathlib_pickle.olean

echo "Note: This benchmark measures the time to load the Mathlib environment."
echo "The optimized pickle/unpickle should be significantly faster than the baseline."
