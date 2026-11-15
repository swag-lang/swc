# Conditional release may-use warning

## Round 1

| Check | Tests | Consumer sweep | Warning sites | Decision |
| --- | --- | --- | --- | --- |
| A local may hold a released pointer after a conditional release | `cwe416_use_after_free.swg`: the warning fires on the stale read; the kept-path read and post-rebind read stay silent. The retained allocator checks both runtime paths without touching physically freed storage. | `safety` and `sanity` pass in Release-safe. All standard-library modules were compiled; the consumer sweep reached every Linux std module, every example, all three apps and both reference workspaces. Reference passes 2/2; examples pass 28/32, with four Windows-only imports unavailable on Linux. The three apps compile, but their native suites expose separate issues: swagcapture requires X11 after 188 tests, swagscope has one full-suite failure after 291 passes (its 30 video tests pass alone), and swagvault has six test failures including two rendering goldens. Earlier DevMode std tests also expose a pixel rendering timeout and a video 4K stress timeout; the GUI menu golden failure reproduces on the pre-campaign compiler. | Three unique source uses in the Linux-compiled `bin/` tree: the corpus positive and two reads in `Threading.createSuspendedNative` (`thread.linux.swg:100,102`). No additional may-use warnings appeared in examples, apps or reference. Windows-only example code that fails on its unavailable Win32/GDI+ imports is outside this Linux warning count. | Keep may facts separate from must proofs and report them as warnings. The measured Linux source count is 3; platform-specific Windows code remains unmeasured on this host. |

## Validation

- DevMode compiler: `safety` passed (JIT and native); `sanity` passed.
- Release-safe compiler: `safety` and `sanity` passed.
- Linux consumer sweep: all std modules compile; 28/32 examples pass; three apps compile, with the native test limits above; both reference workspaces pass. Only the two existing core thread reads add warning sites beyond the corpus positive.
- Isolated GUI comparison: `std gui --test-file tests/cases/golden/menu.anchors.swg` fails with the same two tests on both `b3aec41590` and its parent `08f95f268f`; this is not attributed to the may-use analysis.
- `git diff --check` passed.

## Commit

- Integrated into remote `master` by `b457b0fa70` (after the campaign commit `dbc4b8f4c6`).
