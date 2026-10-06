# Reuse SSA dominance intervals

Five pre-allocation analyses can now copy the dominance intervals from a valid SSA
rename walk for the same CFG identity and build id. They avoid constructing another
instruction dominator tree. No additional persistent per-instruction storage is added.
Nonzero entries, invalid/stale snapshots, and graphs without virtual definitions retain
the existing CFG algorithm. This is a structural reduction in compiler work; no timing
or peak-memory gain was measured.

Validation used the checkout-local Release compiler and Release programs, based on
`7d7024ca0` plus this change. The native optimizer selection passed 281 tests in JIT
and native execution. A rebuilt core module succeeded. All five printed Inflate
functions have identical post-emit instruction bodies to the prior compiler after
normalizing relocation addresses and output ordering. The earlier listing was made
before the concurrent native-emission changes integrated from master; it is a code
identity check, not a timing comparison.

The C++ SSA fixture now checks every pair of instructions in 48 graph shapes, plus
stale/wrong graph, invalid snapshot, nonzero entry and missing-rename fallbacks. Those
internal tests are not included in the Release executable and were not run in this lot.
