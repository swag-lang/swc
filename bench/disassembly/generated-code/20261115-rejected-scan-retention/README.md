# Rejected: retaining the final scan values again

The trial against `6cb558ed24` retained the final indexed comparison values in
idle physical registers and removed the two swap reloads. All twelve checksums,
1,715 C++ tests and four JIT/native scan/alias cases passed. Other task kernels
and runtime bodies were unchanged after matching generated names.

The unchanged 300,000-element seeded input has 2,552,662 left scan reads,
2,911,215 right scan reads and 1,022,129 swaps. Retaining both values trades
3,419,619 additional x86 instructions for 2,044,258 fewer memory reads. Clang 17's
source-verified reference retains these values, while the Swag and MSVC scans use
memory comparisons. This is a trade, not an instruction-count win.

Stage inspection and Git history establish that this is an existing deliberate
choice. `e35b5cb833` and `c68640e492` implemented pre-allocation scan reuse;
`a5246d66a8` subsequently introduced `sinkScanCompareValue` to shorten scans.
The existing pre-allocation rule still works. The new post-allocation trial simply
undid the later rule and reproduced its exact previously retained cost counts.
Its additional CFG analysis is therefore unjustified. No runtime timing was taken
and all experimental compiler/test changes were restored before continuing.

The compressed trial patch, exact linked qsort functions, stage trace, cost
diagnostic, complete verbose Micro comparison and correctness logs retain the
evidence. The diagnostic checksum is `599499929`; it is not a modified benchmark
or a timing workload. The first version of the added execution test used RBX
without preserving it; that test-only error was corrected before its passing run.
No backlog item is added for this completed investigation.
