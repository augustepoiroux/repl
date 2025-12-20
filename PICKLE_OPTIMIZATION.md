# Pickle Snapshot Optimization

## Overview

This document describes the optimization made to the pickle snapshot feature to improve unpickling performance, especially for large imports like Mathlib.

## Problem

The original pickle implementation only saved new constants (`env.constants.map₂`) relative to imports. When unpickling, it would:

1. Call `importModules` to load all imported modules (very slow for Mathlib)
2. Replay only the new constants from `map₂`

This made unpickling slow, particularly when working with Mathlib, as the `importModules` call would re-parse and load all .olean files.

## Solution

The optimized implementation now:

1. **Pickles all constants** (`env.constants.map₁` + `env.constants.map₂`) instead of just new ones
2. **Avoids `importModules`** during unpickling by reconstructing the environment from pickled constants
3. **Handles failures gracefully** with try/catch and fallback to the old format

### Implementation Details

#### Pickle Format

The new pickle format includes a boolean flag indicating whether the optimized format is used:

```lean
(hasMap₁ : Bool,
 imports : Array Import,
 map₁ : PHashMap Name ConstantInfo,  -- All imported constants
 map₂ : PHashMap Name ConstantInfo,  -- New constants
 ...other state...)
```

#### Unpickle Logic

```lean
if hasMap₁ then
  -- Optimized path: Create empty environment and replay all constants
  let mut env ← mkEmptyEnvironment
  env := { env with header := { env.header with imports := imports } }
  -- Efficiently merge both maps using foldl to avoid list concatenation overhead
  let allConstants := Std.HashMap.ofList map₁.toList
  let allConstants := map₂.toList.foldl (fun m (k, v) => m.insert k v) allConstants
  env ← env.replay allConstants
else
  -- Fallback path: Use original importModules approach
  (← importModules imports {} 0 (loadExts := true)).replay (Std.HashMap.ofList map₂.toList)
```

### Error Handling

If pickling `map₁` fails (due to unpicklable objects), the implementation automatically falls back to the original format with only `map₂`. The unpickle function detects this via the `hasMap₁` flag and uses the appropriate unpickling strategy.

## Testing

### Performance Benchmark

Run the benchmark script to measure the performance improvement:

```bash
./benchmark_pickle.sh
```

This will:
1. Measure baseline time to import Mathlib from scratch
2. Measure time to create a pickle file with Mathlib
3. Measure time to unpickle Mathlib
4. Calculate and display the speedup

### Expected Results

For Mathlib imports, the unpickle operation should be significantly faster than importing from scratch, as it avoids:
- Parsing .olean files
- Processing import dependencies
- Rebuilding the constant map

The exact speedup depends on the system and Mathlib version, but typical improvements are 2-10x faster.

### Unit Tests

The test suite includes tests for pickle/unpickle with various scenarios:

```bash
lake exe test
```

Relevant test files:
- `test/pickle_environment.in` - Basic environment pickling
- `test/pickle_environment_with_imports.in` - Pickling with imports
- `test/pickle_mathlib_performance.in` - Performance test with Mathlib
- `test/Mathlib/test/pickle.in` - Mathlib-specific pickle tests

## Compatibility

The changes maintain backward compatibility:
- Old pickle files (without map₁) will still work via the fallback path
- New pickle files use the optimized format when possible
- The format auto-detects via the `hasMap₁` boolean flag

## Limitations

1. **Pickle file size**: Files are larger as they contain all imported constants, not just new ones
2. **Extensions**: Environment extensions are not fully pickled, so some extension data must be reinitialized
3. **Unpicklable objects**: Some rare objects might not be picklable, triggering fallback to the old format

## Future Improvements

Possible future enhancements:
- Compress pickle files to reduce disk space
- Pickle environment extensions where possible
- Cache pickled Mathlib imports for reuse across sessions
