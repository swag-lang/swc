# Core at a glance

Core supplies the building blocks used throughout the standard workspace. Pick
an area by the problem you need to solve:

| Goal | Start with |
|---|---|
| Store an ordered sequence | [[Core.Array]] or [[Core.StaticArray]] |
| Associate keys with values | [[Core.HashTable]], [[Core.HashSet]], [[Core.OrderedMap]], or [[Core.OrderedSet]] |
| Work at both sequence ends | [[Core.Deque]] |
| Consume work by priority | [[Core.PriorityQueue]] |
| Own and edit UTF-8 text | [[Core.String]] |
| Inspect borrowed UTF-8 data | [[Core.Utf8]] and slices |
| Work with files and paths | [[Core.File]], [[Core.Directory]], and [[Core.Path]] |
| Encode structured data | [[Core.Serialization]] |
| Measure time or dates | [[Core.Time]] |
| Run concurrent work | [[Core.Jobs]], [[Core.Threading]], and [[Core.Sync]] |
| Inspect types at runtime | [[Core.Reflection]] |
| Hash or checksum bytes | [[Core.Hash]] |

Most Core types are ordinary values with deterministic cleanup. Collections and
strings own their buffers; copying them copies their content. Pointer and slice
fields are commonly borrowed views, so their declaring type documents the
corresponding lifetime.

Operations that can fail use Swag's `fail` mechanism. Propagate a failure with
`try`, or catch it at the boundary where the program can add useful context.
