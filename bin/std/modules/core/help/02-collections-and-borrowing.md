# Collections and borrowing

[[Core.Array]] is the default growable sequence. [[Core.HashTable]] provides
key-value lookup, [[Core.HashSet]] stores unique keys, and [[Core.StaticArray]]
keeps a small growable sequence inline before allocating. [[Core.OrderedMap]]
and [[Core.OrderedSet]] trade insertion cost for sorted traversal and range
queries. [[Core.Deque]] serves both ends of a sequence, while
[[Core.PriorityQueue]] exposes the next element selected by a comparator.

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

## Ordering and ranges

Ordered collections and priority queues take an explicit comparator. Its
arguments are borrowed. Return a negative value when the left argument belongs
before the right argument, zero when their ordering keys are equal, and a
positive value otherwise.

```swag
var ranking: OrderedMap'(u32, String)
ranking.initialize(func(left, right: const *u32)->s32 => left[] <=> right[])
ranking.add(20, "silver")
ranking.add(10, "gold")

for entry in ranking.range(10, 30) do
    Console.printLn(entry.key, ": ", entry.value)

var work: PriorityQueue'u32
work.initialize(func(left, right: const *u32)->s32 => left[] <=> right[])
work.push(30)
work.push(10)
let first = work.pop()
```

Ranges are half-open: `range(lower, upper)` contains keys greater than or equal
to `lower` and less than `upper`. A range is a borrowed slice and is invalidated
by insertion or removal.

## Ownership rule

An owning collection controls its elements and buffer. A slice returned by
`toSlice`, `range`, a pointer returned by lookup, or an iterator variable borrows that
storage. Adding, removing, resizing, clearing, or freeing the collection can
invalidate those borrowed values.

Prefer a slice when a function only needs temporary sequential access. Prefer an
owned collection when the callee must retain or modify the data independently.

## Capacity and reuse

Repeated insertion can grow a collection. Reserve capacity before a known batch
when pointer stability or allocation cost matters, and use `clear` when the
allocation should be retained for reuse. Use `free` when the capacity itself
should be returned immediately.
