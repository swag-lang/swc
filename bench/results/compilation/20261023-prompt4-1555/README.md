# Structural compiler-speed work, 2026-10-23 afternoon

This prompt-4 session starts from `b405557e70` on
`perf/prompt4-20261023-1555` in an external worktree. Planned speed work uses the
checkout-local DevMode compiler with six workers. No timing, profiling, or benchmark
campaign was run.

| Retained change | Compiler work removed | Equivalence argument | Validation |
| --- | --- | --- | --- |
| Share stateless sanitizer checks across function runs | Reconstructing eight empty check objects and their pointer array on the stack for every sanity-enabled function | Each check class has no instance fields; its virtual methods read only call arguments. The `Sanitizer` remains local to each function run, so shared check instances carry no cross-run state. Check selection and order are unchanged. | DevMode build; all 85 sanity tests passed. |

The change is structural; no elapsed-time or memory claim is made.
