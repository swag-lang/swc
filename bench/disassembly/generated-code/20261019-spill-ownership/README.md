# Private spill ownership across stack adjustments

The dead-spill removal added by stable-local reuse used the allocator's raw
SP-displacement envelope as ownership. An outgoing pointer argument at the same
displacement after an SP subtraction can instead refer to source memory below
the allocator reserve. Skipping a known register-only call then deleted its live
payload store. The new addressed-outgoing-slot regression fails before this fix.

Register allocation now records the reserved interval relative to incoming SP.
Further allocation sweeps extend it; prologue insertion relocates it below all
saved registers, including merged allocations. Dead-store removal proves the
complete normalized store lies in this owned interval before skipping aliases
or calls. Missing stack-depth information still declines the transform.

Validation: 1,541 full C++ tests pass. The two added families cover an already
escaped pointer, indirect reads, calls, merged/separate prologues and a forced
frame pointer. All twelve benchmark checksums match. Grouping overloaded and
generated function ordinals, every function's instruction, memory, call and
loop counts is unchanged from the accepted spill-reuse batch, including nbody's
396 instructions / 163 memory operands per timestep. This is a correctness
repair with no new runtime speed claim. Native/JIT suite results are recorded
with the session report after they complete.
