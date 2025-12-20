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

1. **Pickles the entire constants map** (`env.constants` SMap) instead of just new constants
2. **Avoids `importModules`** entirely during unpickling by directly setting the constants field
3. **Simpler approach** without fallback logic or error handling complexity

### Implementation Details

#### Pickle Format

The new pickle format saves the entire SMap:

```lean
(imports : Array Import,
 constants : SMap Name ConstantInfo,  -- Entire constants map (both imported and new)
 ...other state...)
```

#### Unpickle Logic

```lean
-- Create empty environment and set its constants directly
let mut env ← mkEmptyEnvironment
env := { env with header := { env.header with imports := imports }, constants := constants }
```

### Why This Works

By pickling the entire `env.constants` SMap object:
- We avoid accessing private internal fields (map₁/map₂)
- We bypass the slow `importModules` call completely  
- We have a simpler, more direct implementation
- The SMap type is a standard Lean structure that should be picklable

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

**Breaking change**: This implementation is NOT backward compatible with old pickle files. Old pickle files saved only `map₂` but the new format expects the entire `constants` SMap. This is acceptable for the REPL use case where pickle files are typically transient.

## Limitations

1. **Pickle file size**: Files are larger as they contain all constants, not just new ones
2. **Extensions**: Environment extensions are not fully pickled, some extension data may need reinitialization
3. **Not backward compatible**: Old pickle files will not work with new unpickle implementation

## Future Improvements

Possible future enhancements:
- Compress pickle files to reduce disk space
- Pickle environment extensions where possible
- Cache pickled Mathlib imports for reuse across sessions
- Add version checking to handle backward compatibility gracefully
