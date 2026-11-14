# Reuse the prologue's saved SIMD registers for private spills

Batch 21, based on 87bfb9089. Release compiler and optimized programs.
The prologue publishes the exact persistent SIMD registers it saves. Private
spill caching can borrow one only when physical liveness proves it dead at every
entry and untouched throughout the loop. No new save, restore or unwind record
is introduced; arbitrary memory stores are not treated as evidence of ABI saves.

Slice.predictIntraPlane changes from 2,126 instructions / 697 memory operations /
119 explicit RSP accesses to 2,115 / 681 / 103, with seven pushes throughout.
Already saved XMM6-XMM11 carry values across a cold call, removing cache restores
and admitting another private home. The normalized diff is retained beside this
report. The other 321 H.264 bodies retain their counts; the 322-body panel goes
from 42,796 / 9,583 / 2,011 to 42,785 / 9,567 / 1,995, with 967 pushes.

Nbody, ChaCha, CSV and Dijkstra retain their counts and pass their checksums.
The full native Release campaign passes 3,639 tests in JIT and native execution,
including expected recovery probes; all 23 H.264 tests pass too. Internal fixtures
cover absent save metadata, live/used registers and both ordinary/merged save
areas; the Release compiler does not execute these C++ fixtures.
No runtime timing claim is made.

Metadata-reuse changes through 750b02944 were reviewed and imported before merge.
They reuse the same reaching values and resolved argument types; the full tests
and counts above describe 87bfb9089 plus this change, before that late import.
