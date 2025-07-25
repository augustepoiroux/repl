# A read-eval-print-loop for Lean 4

## About this Fork

This is a fork of the original Lean REPL that supports multiple Lean versions. The versioning system is designed to ensure compatibility across different Lean releases:

- Each release of this REPL fork, starting from v1.0.9, is tagged with both the REPL version and the corresponding Lean version it supports.
- Tags follow the format `vX.Y.Z_lean-toolchain-vA.B.C`, where:
  - `vX.Y.Z` is the REPL version
  - `vA.B.C` is the Lean version (including intermediate Lean versions with suffixes like `-rc1`)
- All recent REPL features and bug fixes are backported to previous Lean versions.
- All Lean versions are tested in the CI pipeline. Some Lean versions do not have a corresponding Mathlib release, in which case, Mathlib-related tests are skipped.

**Note:** Some output differences specific to each Lean version may occur.

## Changelog

### v1.2.1-dev

- Add support for Lean v4.22.0-rc4

### v1.0.13

- Add support for Lean v4.22.0-rc4

### v1.2.0-dev

- Add `"declarations": true` option to extract fine-grained information about declarations [#119](https://github.com/leanprover-community/repl/pull/119)
- Incorporate v1.0.12 changes to v1.1.1-dev

### v1.0.12

- File mode has now an `env` field [#99](https://github.com/leanprover-community/repl/pull/99)
- Various REPL fixes: [#106](https://github.com/leanprover-community/repl/pull/106), [#98](https://github.com/leanprover-community/repl/pull/98), [#72](https://github.com/leanprover-community/repl/pull/72)
- Syntax nodes now export a few more attributes [#89](https://github.com/leanprover-community/repl/pull/89)
- Add support for Lean v4.22.0-rc3

### v1.1.1-dev

- Add support for Lean v4.22.0-rc1 and v4.22.0-rc2.

### v1.0.11

- Add support for Lean v4.22.0-rc1 and v4.22.0-rc2.

### v1.1.0-dev

- Incorporate the experimental prefix state optimization from the `auto-prefix-optimization` branch, along with a few fixes for the tactic mode. [#110](https://github.com/leanprover-community/repl/pull/110), [#109](https://github.com/leanprover-community/repl/pull/109), [#108](https://github.com/leanprover-community/repl/pull/108), [#106](https://github.com/leanprover-community/repl/pull/106)

### v1.0.10

- Add support for Lean v4.21.0.

### v1.0.9

- First version using the new tagging system: one tag per Lean version.
- Add support for all Lean versions between 4.19.0 and v4.21.0-rc3 (+ v4.19.0-rc3).

### v1.0.8

- Add support for Lean v4.19.0. **Note:** v4.19.0-rc3 has been forgotten and is added in v1.0.9.

### v1.0.7

- Fix `auxiliary declaration cannot be created when declaration name is not available` issue for Lean v4.18.0. See <https://github.com/leanprover-community/repl/issues/44#issuecomment-2814069261>

### v1.0.6

- Add kernel check for proofs in tactic mode.

### v1.0.5

- Add support for Lean v4.19.0-rc1 and v4.19.0-rc2

### v1.0.4

- Add support for Lean v4.18.0

### v1.0.3

- First version using the new branching and versioning system. Branch name = REPL version, commit names = Lean versions.

## Usage

Run using `lake exe repl`.
Communicates via JSON on stdin and stdout.
Commands should be separated by blank lines.

The REPL works both in "command" mode and "tactic" mode.

## Command mode

In command mode, you send complete commands (e.g. declarations) to the REPL.

Commands may be of the form

```json
{ "cmd" : "def f := 2" }
```

```json
{ "cmd" : "example : f = 2 := rfl", "env" : 1 }
```

The `env` field, if present,
must contain a number received in the `env` field of a previous response,
and causes the command to be run in the existing environment.

If there is no `env` field, a new environment is created.

You can only use `import` commands when you do not specify the `env` field.

You can backtrack simply by using earlier values for `env`.

The response includes:

- A numeric label for the `Environment` after your command,
  which you can use as the starting point for subsequent commands.
- Any messages generated while processing your command.
- A list of the `sorry`s in your command, including
  - their expected type, and
  - a numeric label for the proof state at the `sorry`, which you can then use in tactic mode.

Example output:

```json
{"sorries":
 [{"pos": {"line": 1, "column": 18},
   "endPos": {"line": 1, "column": 23},
   "goal": "⊢ Nat",
   "proofState": 0}],
 "messages":
 [{"severity": "error",
   "pos": {"line": 1, "column": 23},
   "endPos": {"line": 1, "column": 26},
   "data":
   "type mismatch\n  rfl\nhas type\n  f = f : Prop\nbut is expected to have type\n  f = 2 : Prop"}],
 "env": 6}
```

showing any messages generated, and sorries with their goal states.

## File mode

There is a simple wrapper around command mode that allows reading in an entire file.

If `test/file.lean` contains

```lean
def f : Nat := 37

def g := 2

theorem h : f + g = 39 := by exact rfl
```

then

```
echo '{"path": "test/file.lean", "allTactics": true}' | lake exe repl
```

results in output

```json
{"tactics":
 [{"tactic": "exact rfl",
   "proofState": 0,
   "pos": {"line": 5, "column": 29},
   "goals": "⊢ f + g = 39",
   "endPos": {"line": 5, "column": 38}}],
 "env": 0}
 ```

## Tactic mode (experimental)

To enter tactic mode issue a command containing a `sorry`,
and then use the `proofState` index returned for each `sorry`.

Example usage:

```json
{"cmd" : "def f (x : Unit) : Nat := by sorry"}

{"sorries":
 [{"proofState": 0,
   "pos": {"line": 1, "column": 29},
   "goal": "x : Unit\n⊢ Nat",
   "endPos": {"line": 1, "column": 34}}],
 "messages":
 [{"severity": "warning",
   "pos": {"line": 1, "column": 4},
   "endPos": {"line": 1, "column": 5},
   "data": "declaration uses 'sorry'"}],
 "env": 0}

{"tactic": "apply Int.natAbs", "proofState": 0}

{"proofState": 1, "goals": ["x : Unit\n⊢ Int"]}

{"tactic": "exact -37", "proofState": 1}

{"proofState": 2, "goals": []}
```

You can use `sorry` in tactic mode.
The result will contain additional `proofState` identifiers for the goal at each sorry.

At present there is nothing you can do with a completed proof state:
we would like to extend this so that you can replace the original `sorry` with your tactic script,
and obtain the resulting `Environment`

## Pickling

The REPL supports pickling environments and proof states to disk as `.olean` files.
As long as the same imports are available, it should be possible to move such an `.olean` file
to another machine and unpickle into a new REPL session.

The commands are

```json
{"pickleTo": "path/to/file.olean", "env": 7}

{"pickleTo": "path/to/file.olean", "proofState": 17}

{"unpickleEnvFrom": "path/to/file.olean"}

{"unpickleProofStateFrom": "path/to/file.olean"}
```

The unpickling commands will report the new "env" or "proofState" identifier that
you can use in subsequent commands.

Pickling is quite efficient:

- we don't record full `Environment`s, only the changes relative to imports
- unpickling uses memory mapping
- file sizes are generally small, but see <https://github.com/digama0/leangz> if compression is
  desirable

## Using the REPL from another project

Set up your project as usual using `lake new` or `lake init`
(or the interactive setup GUI available via the VSCode extension under the `∀` menu).

In that project, add `require` statements in the `lakefile.lean` for any dependencies you need
(e.g. Mathlib). (You probably should verify that `lake build` works as expected in that project.)

Now you can run the REPL as:

```shell
lake env ../path/to/repl/.lake/build/bin/repl < commands.in
```

(Here `../path/to/repl/` represents the path to your checkout of this repository,
in which you've already run `lake build`.)

The `lake env` prefix sets up the environment associated to your local project, so that the REPL
can find needed imports.

## Future work

- Replay tactic scripts from tactic mode back into the original `sorry`.
- Currently if you create scoped environment extensions (e.g. scoped notations) in a session
  these are not correctly pickled and unpickled in later sessions.

## Running Tests

To run the test suite (which wraps `test.sh` and checks the REPL against expected outputs), use:

```sh
lake exe test
```

This will execute all tests in the `test/` directory and propagate the exit code, making it suitable for CI and scripting.
