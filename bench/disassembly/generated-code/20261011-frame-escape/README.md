# Keep frame privacy across branches before the address escapes

Baseline: `c7e07a8cd`. Release programs were compiled with the checkout-local
DevMode compiler, six workers, isolated outputs and `--validate-micro`.
No benchmark source, workload, checksum or timed boundary changed.

| Task / competitor | Bottleneck | Mechanism | Executed path | Other tasks | Timing | Checks | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| binarytrees / Java HotSpot | A header read hides a dead local request fill after the null guard | Prove no frame escape can reach that read | One fewer 16-byte store per nonnull free; 46 to 45 function instructions, 15 to 14 memory operands, same three calls | Only the same benchFree store disappears in all twelve tasks; all other functions and loops retain counts | Not measured | 1,374 C++ tests; dead_local_fill.swg JIT and native; twelve checksums; eight expected pointer errors | Landed, unconfirmed |

`benchFree` initializes a 96-byte allocator request, then overwrites its address
and size fields. Reading the allocation header between those writes cannot
alias the request: the request address has not yet escaped. The existing
byte-coverage dead-store analysis already combines the two eight-byte writes;
it previously lost the privacy proof at the branch guarding a null argument.
The final executable now omits `vmovups [rsp + 0x50], xmm0`, keeping the scalar
stores to `[rsp + 0x50]` and `[rsp + 0x58]`. Its stack frame stays 0x98 bytes,
with the same saved registers and allocator calls. This saves one store for
each of binarytrees' 674,478 allocated and released nodes. Checksum: 674478.

The shared CFG query follows successors from every escape, including cycles.
A later textual escape on another branch can reach an earlier load through a
loop, so recording only the first escape would be unsound. Unknown targets,
address-taken labels and absent roots return a conservative reachable mask.
The dead-store scan still stops at calls and block boundaries. Known frame
reads retain byte-precise overlap checks. The whole-frame proof is conservative
when an unrelated frame object has escaped. SLP uses the same query in place
of its existing reverse reachability walk.

The query costs O(V + E + R) time and O(V) auxiliary memory for V instructions,
E CFG edges and R escape roots. MemToReg computes it lazily, at most once per
dead-store scan, only when an unknown read threatens a pending store. SLP
retains a fresh query at each existing privacy check, avoiding stale reachability
across graph rewrites. No compiler-time improvement is claimed.

C++ regression coverage includes a forward branch with no prior escape,
an escape on a previous iteration, and separate escape branches where only
the later textual escape reaches the loop. Existing global and constant-copy
cases now contain actual back edges. The native fixture also checks an early
guard followed by reads through an unrelated pointer. Its first draft correctly
failed because a value pointer to an array requires an explicit dereference
before indexing. The diagnostic now states the required arithmetic-pointer
category and the actual value-pointer category; its ID and source span are
unchanged. A new expected-error case covers that array-pointer form. The fixed
fixture and all eight expected-error cases pass.

The competitor was inspected with Temurin OpenJDK 25.0.4.1+1, ordinary javac
and default tiered HotSpot, adding only diagnostic printing of `Bench.bottomUp`
and `Bench.check`. The captured C2 bytes were decoded with LLVM objdump because
hsdis was unavailable. The allocation fast path increments a thread-local bump
pointer by 24 bytes, checks its limit and writes the object header/fields.
Java has GC and write barriers; it does not explicitly free each node inside
the timer. Swag's explicit per-node allocator request is therefore a runtime
boundary cost, not evidence that every difference is a missing peephole. This
batch removes only a proved dead request write and preserves reclamation.

[microdiff.json](microdiff.json) records all twelve checksums and changed
function counts, including runtime code. The session campaign will determine
whether the target moves beyond its null band.
