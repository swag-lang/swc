# Static micro-pass batch 19: Predecessor and return bookkeeping, early load rejection

Build 549, source commit `b474bcb7f`.
All checks passed with exit code 0:

- [DevMode build 549](batch19-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch19-cpp.log): 763 passed, including three added tests.
- [Native devmode](batch19-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch19-native-release.log): 3,131 passed; generated executable passed.

The checkout-local commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

LICM no longer hashes every instruction reference into a predecessor-index table each
round. The CFG snapshot follows storage order and remains unchanged throughout planning;
the instruction before a header therefore has ordinal `header - 1`. The reference equality
and loop-membership guards remain explicit. Existing preheader and loop tests cover this path.

PrologEpilog removes its temporary return-reference list and walks from the original first
instruction after inserting the prologue. Iterators hold storage plus stable references;
epilogue helpers insert only before the current return, preserving its successor. Return
order, insertion anchors and debug provenance remain unchanged. One new test checks two
returns, their original references, and the exact ABI save/restore sequence.

ValueNumbering rejects physical memory bases before constructing relocation and frame
classification tables. Such bases already failed the later SSA-key operand check. It also
moves the existing non-64-bit address rejection before those tables. Memory epochs still
advance first, and all preparation reads the same immutable snapshot. The physical-base
check adds one cheap register-class test to admitted virtual loads. Two tests cover opaque
stack/general/RIP bases with valid relocations followed by a numberable load pair, and
rejected 32-bit addresses followed by accepted 64-bit addresses with 32-bit data.

All families received independent review. No benchmark execution or performance comparison
belongs to this batch.
