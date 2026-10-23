# Alternating compiler speed and memory, 2026-10-23

This session alternates prompts 4 and 5 until 12:00 Europe/Paris. The campaigns use separate
external worktrees under `%LOCALAPPDATA%/swc-agent-builds/alternate45-20261023-0730`, with
checkout-local compilers and at most six compiler workers. Prompt 4 does not use timing or
profiling; every retained speed change has a structural proof.

| Prompt | Retained change | Compiler work removed | Validation |
| --- | --- | --- | --- |
| 4 | Skip a second full rank comparison for candidates with the same UFCS call shape | `compareCandidatesIgnoringReceiver` already compares all explicit-argument ranks and the default/generic tie-breakers. When both candidates bind a receiver, only their receiver rank remains for the full ranking; when neither binds it, the full ranking is already complete. This removes the repeated explicit-argument walk while preserving receiver-kind and receiver-constness tie-breakers. | DevMode build; semantic function filter: 55 ordinary and 28 expected-error inputs; generic filter: 60 ordinary and 28 expected-error inputs. |
| 5 | Drop retained SSA buffers when a worker moves from an outlier function to a much smaller one | Reuse remains intact for similar function sizes; an oversized per-worker `MicroSsaState` is released before the next small function begins. | DevMode build; 1,627 C++ tests passed, including SSA; three alternating six-worker `core_rebuild` and `hello_build` rounds. [Memory results and profile limits](../../memory/20261023-alternate45/README.md). |

Prompt 4 makes no elapsed-time or memory claim. Prompt 5's measured before-and-after results are
in the linked memory report.
