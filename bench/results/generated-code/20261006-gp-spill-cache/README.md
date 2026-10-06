# Keep private spill homes in already saved integer registers

Batch 20, based on e7dcaeac5. Release compiler and optimized programs.
Private spill caching now prefers an already saved integer register that is dead
at every entry and untouched throughout the loop. Stack/debug bases and
frame pointers are excluded. The existing prologue scan is shared with bitwise
operand hoisting; no save, restore or unwind record is added.

A register preserved by every call can also cache a home in a loop that calls on
every trip. Clobbered caches retain the call-free-path requirement. The existing
byte-range, stack-motion, entry/exit and write-through proofs are unchanged.

H.264 extendPlane retains 97 instructions and four pushes while explicit memory
operations fall from 27 to 15 and RSP accesses from 17 to five. Three values cross
two copy calls in RDI/R12/R13 instead of six stores and six reloads. The fourth
home remains in memory. Its normalized instruction diff is retained here.

Fresh baseline and candidate each print 322 H.264 bodies: concurrent library
reachability work removed twelve bodies from the older 334-body panel. The new
panel retains 42,796 instructions and 967 pushes; memory operations fall from
9,595 to 9,583 and RSP accesses from 2,023 to 2,011. All other bodies and the CSV,
nbody, ChaCha and Dijkstra counts are unchanged. Do not attribute the smaller
panel to this optimization. No runtime timing claim is made.

Validation: 293 native optimizer and 23 H.264 tests pass in Release JIT and native
execution, plus the four benchmark checksums. Internal fixtures cover mandatory
calls, missing saves, used/live-out registers, protected debug bases and
frame pointers; those C++ fixtures are not executed by the Release compiler.

Integration: subsequent master changes through bad64df6f stop exporting generated
member-wise equality operators. The combined compiler is rebuilt in Release and
the optimizer/H.264 checks are repeated after excluding frame pointers even when
no explicit frame-pointer request was set.
The final 322-body dump retains every grouped instruction/memory/RSP/push count
from the candidate above, including extendPlane at 97/15/5/four.
Later metadata-reuse changes through 45ff95471 were reviewed and imported before
merge. They preserve the allocator decisions and resolved payloads; the counts
and repeated tests above describe bad64df6f, before that final import.
