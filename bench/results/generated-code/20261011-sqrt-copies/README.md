# Retain scalar roots without result copies

Baseline: `3de18939a`. Both code captures use the checkout-built DevMode compiler,
Release programs, six workers, and `--validate-micro`. The preserved baseline
compiler SHA-256 is `fbd9614a20d75eadd8bf807a29ea5ba148b638a0e4759c54ad2cc8e930c06134`.

| Task / current competitor | Observed cost | Mechanism | Executed path | Other code | Timing | Validation | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| raytrace / C++ MSVC | Each evaluated sphere root is copied to its retained register | Retarget scalar sqrt, then redirect remaining reads until a full overwrite | Root, copy, sign change, subtract: 4 to 3 instructions per evaluated root | nbody and chacha retain their task instruction/memory/call counts; allocator paths retain their counts | Not measured | 1,373 C++ tests; native `slp_double.swg` in DevMode, JIT and native; three benchmark checksums | Landed, unconfirmed |

The post-allocation rule requires a full 128-bit copy and a bounded straight-line
interval. Calls, labels, branches, destination writes, read-modify-write source
operations and partial source overwrites reject it. Every crossed instruction is
claimed against competing rewrites. The search takes at most sixteen instructions
per candidate; it adds no global analysis.

The original emitted sequence repeats in all four unrolled sphere arms:

```asm
vsqrtsd xmm8, xmm8, xmm8
vmovups xmm9, xmm8
vxorpd  xmm10, xmm10, [sign_mask]
vsubsd  xmm8, xmm10, xmm8
```

The candidate emits:

```asm
vsqrtsd xmm9, xmm8, xmm8
vxorpd  xmm10, xmm10, [sign_mask]
vsubsd  xmm8, xmm10, xmm9
```

Negative discriminants skip the root and receive no instruction-count saving.
Each evaluated root saves one copy; up to four copies disappear per `intersect`
call. Its whole body changes from 177 to 173 instructions, with 44 memory operands,
no calls, and the same frame/saves. These are final native instructions verified
with llvm-objdump, not only pre-allocation counts.

MSVC 19.50.35726.0 was rebuilt with the harness's `/O2 /EHsc /std:c++20` options.
Its scalar roots already name an independent destination. Its default floating
contract also keeps a conditional CRT `sqrt` fallback; Swag's aggressive Release
policy differs, so that fallback is not counted as a missing optimization.
Both programs return raytrace checksum `56061776`.

The other checksums are nbody `169096566666` and chacha `633277775`. Full captured
functions were compared, including the allocator. The apparent `Swag.atomicGet`
two-to-three-instruction change is only a swap of the dump's duplicate-name
suffixes: the 32-bit and 64-bit overload bodies are individually unchanged.

The new internal tests cover both scalar widths, whole-vector observations,
positive and negative zero, negative inputs, infinity, independent root sources,
multiple readers, and rejection boundaries. Native `slp_double.swg` executes one
test through both JIT and native code under the DevMode program configuration.
No twelve-task comparison or paired timing belongs to this narrow first batch;
the grouped session campaign will determine whether its runtime gain is measurable.
