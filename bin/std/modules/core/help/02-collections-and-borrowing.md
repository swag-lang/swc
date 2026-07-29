# Collections and borrowing

[[Core.Array]] is the default growable sequence. [[Core.HashTable]] provides
key-value lookup, [[Core.HashSet]] stores unique keys, and [[Core.StaticArray]]
keeps a small growable sequence inline before allocating.

```swag
using Core

var names: Array'String
names.add("Ada")
names.add("Grace")

var scores: HashTable'(String, u32)
scores.add("Ada", 10)
scores.add("Grace", 12)

if let entry = scores.tryFind("Ada") do
    Console.printLn(entry.value)
```

## Ownership rule

An owning collection controls its elements and buffer. A slice returned by
`toSlice`, a pointer returned by lookup, or an iterator variable borrows that
storage. Adding, removing, resizing, clearing, or freeing the collection can
invalidate those borrowed values.

Prefer a slice when a function only needs temporary sequential access. Prefer an
owned collection when the callee must retain or modify the data independently.

## Capacity and reuse

Repeated insertion can grow a collection. Reserve capacity before a known batch
when pointer stability or allocation cost matters, and use `clear` when the
allocation should be retained for reuse. Use `free` when the capacity itself
should be returned immediately.
