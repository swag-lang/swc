# Prompt 2 session measurement

The full campaign at `78ccdd423` (three integrated batches) passed all twelve
checksums across every runtime, but the harness rejected its timings.
The reference workload moved 54.8% across the campaign, beyond the 40% limit,
and unchanged build controls diverged by 27.6%, beyond the 25% limit.
The complete record is [20261011-195347.json](../../rejected/20261011-195347.json).
No new history entry was accepted. The previous accepted campaign remains
`20261011-163035`; its indices and competitive ratios are not updated from
these rejected samples. All three batches remain landed, unconfirmed.

Command: `bin\swc.exe --num-cores 6 tools\bench.swgs --no-build --swc-cores 6
--label "prompt 2 20261011 group 1"`, using the Release compiler built from the
measured revision with six MSBuild and C++ compilation workers. No session
builds or tests ran alongside the measurements.
