# Static micro-pass batch 13: Occurrence maps, sinking and saved registers

Build 542, source commit `637964af8`, based on the twelfth validated batch in master.
All checks passed with exit code 0:

- [DevMode build 542](batch13-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch13-cpp.log): 743 passed.
- [Native devmode](batch13-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch13-native-release.log): 3,131 passed; generated executable passed.

The checkout-local tool commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| Induction-variable analysis stores count and first reference together | Two hash tables and duplicate lookups for uses and loop definitions | Count increments, first-reference selection and candidate order are unchanged, including adjacent-copy checks. |
| Sink-to-use collects counts with instruction effects and block IDs | A separate instruction walk and redundant buffer initialization | Every entry is written before use; dense register indices retain definition-before-use order. |
| Sink-to-use removes the moved-consumer set | Hash insertions and lookups that could never match | Candidate indices are visited in ascending order and every consumer lies strictly later. Moves still apply in original order. |
| Sink-to-use combines operand eligibility and virtual-read counting | A duplicate operand loop | Both rejection conditions remain identical. |
| Prolog/epilog classifies concrete registers once | Repeated ABI classification and persistent-register list searches | Integer and float masks are disjoint; frame-pointer naming is handled before the definition gate; unusual registers keep the original fallback. |
| SLP compacts successful seed groups in place | A second vector allocation and copies of every accepted group | Tree construction and survivor order remain unchanged; tree keys own their data and retain no group references. |

Five added C++ tests cover repeated integer/float persistent definitions, frame-pointer naming, sinking chains and operand clusters, induction occurrence counts with adjacent copies, and accepted/rejected/accepted SLP groups.

Independent cross-review covers the changed pass families. No generated-code optimization rule or iteration budget changes.

No benchmark execution or performance comparison belongs to this batch.
