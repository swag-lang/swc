# Compiler memory work, 2026-10-30

The objective is to reduce compiler memory and the DevMode/Release gap while giving
compilation speed priority. Changes with a static storage or work reduction are grouped;
builds and comparative measurements are periodic checkpoints, not a per-edit requirement.

## Debugger-only metadata

`SWC_DEBUG_MODE=1` now owns the metadata maintained only for interactive C++ inspection.
MSBuild exposes it through `SwcDebugMode=true` and writes a separate `swc.dbg.exe` with PDB
information and separate intermediates. Normal DevMode keeps assertions, race detection,
compiler validators, allocator checks and unit tests.

Static x64 layout consequences:

| Stored value | Previous DevMode | Normal DevMode after this change |
| --- | ---: | ---: |
| `StrongRef<T>` | 16 bytes | 4 bytes |
| `SourceCodeRef` | 32 bytes | 8 bytes |
| `Token` | 56 bytes | 12 bytes |

The reference pointer, token text pointer, token source pointer, full token location and AST
visitor inspection context remain available in debug mode. Default DevMode no longer computes
line/column positions on every token or refreshes the inspection location on AST traversal.
No lookup, packing, allocation or replacement side table is added to recover these saved bytes.
Compile-time size assertions protect the compact representations.

The AST visitor inspection test is registered only when its inspection fields exist. All
semantic traversal tests and the ordinary compiler checks remain enabled in DevMode.

This batch has not yet been compiled or measured. These are local representation savings,
not a measured process peak or a measured compilation speedup. The preserved pre-change
3.6.0 executables and frozen workloads from the
[integration report](../20261030-mimalloc360/README.md) provide the comparison checkpoint.

## Empty members and record padding

- `SmallVector` no longer reserves an aligned word for its empty `std::allocator` member.
  Its inline capacity, growth policy, object lifetimes and allocation calls are unchanged.
- `FlatKeyMap` uses the same attribute for its empty occupied-slot tracker when tracking is
  disabled. Tracking-enabled maps retain their vector and behavior.
- `ConstantKind` fits in one byte. Placing the borrowed-payload flag next to it eliminates
  eight padding bytes per `ConstantValue`: 56 to 48 bytes without debugger metadata, 72 to
  64 with it. Copy/move initialization order follows declaration order; kind values and hashes
  are unchanged.
- `DataSegmentRelocation` places its boolean next to its byte-sized kind: 32 to 24 bytes on
  x64. The function-relocation initializer follows the new member order. Serialized cache keys
  already encode individual fields, not this in-memory record.

The empty-member attribute chooses `msvc::no_unique_address` when supported, as the installed
MSVC STL does. Microsoft's [ABI explanation](https://devblogs.microsoft.com/cppblog/msvc-cpp20-and-the-std-cpp20-switch/#msvc-extensions-and-abi)
documents why the standard spelling alone does not enable this optimization in the MSVC ABI.
Other compilers use the standard attribute. These changes add no side table, indirection,
allocation, hash lookup or compaction pass; the storage savings apply to Release too.
