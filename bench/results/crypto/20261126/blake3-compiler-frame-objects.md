# Preserve stores at frame-object boundaries

The BLAKE3 width-eight experiment exposed a scalar compiler defect.
A Release build of an 8 × 8 array transpose could erase writes to a
temporary array when the array started at the preceding object's
end address. Dead-store elimination now uses the strict upper bound
on the frame-object ends, consistent with the half-open ranges used
to classify reads and pointer escapes.

The exact test compiler and runtime were built from
`44e09064f1cef5af4258c0decaeb670e38053378` in DevMode. The comparison
recompiled only `Pass.MemToReg.cpp` with the one-line correction and
relinked it against the same remaining objects. Both compilers ran
the new native transpose test with Micro validation enabled. The
baseline failed in Release and the candidate passed. The test also
passed with both compilers in Release-safe. The candidate passed all
four native allocator contract tests.

All 12 Release MicroDiff task checksums matched on Linux x86-64.
The two generated helper name changes had identical instruction
bodies. The only change in the normalized listings was a vector
clear and one 16-byte stack store in `Allocator.retireThreadHeap`.
They initialize the two-element list temporary on each of 45 size
class iterations, up to 90 additional instructions and 720 bytes of
stack writes per retired heap. This work runs during heap retirement.
The generated instructions for the benchmark kernels matched.

[Regression fixture](../../../../bin/unittests/native/optimizer/transpose_frame_temp.swg) ·
[MicroDiff runner](../../../scripts/microdiff.py)
