import Lake
open Lake DSL

package «repl-mathlib-tests» where
  -- add package configuration options here
  require mathlib from git "https://github.com/leanprover-community/mathlib4" @ "v4.8.0"

@[default_target]
lean_lib «ReplMathlibTests» where
  globs := #[.submodules `test]
  -- add library configuration options here