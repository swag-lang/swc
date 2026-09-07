# Collections and borrowing

[[Core.Array]] is the default growable sequence. [[Core.HashTable]] provides
key-value lookup, [[Core.HashSet]] stores unique keys, and [[Core.StaticArray]]
keeps a sequence inline with a fixed maximum capacity. [[Core.OrderedMap]]
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

Use [[Core.Deque.frontPtr]], [[Core.Deque.backPtr]], or [[Core.PriorityQueue.peekPtr]]
to inspect an element without copying it. Their read-only overloads also work when
the element owns a resource and cannot be copied. Borrowing either end of a deque
does not allocate or move its elements.

## Capacity and reuse

Repeated insertion can grow a collection. Reserve capacity before a known batch
when pointer stability or allocation cost matters, and use `clear` when the
allocation should be retained for reuse. Use `free` when the capacity itself
should be returned immediately.

For [[Core.Deque]], [[Core.PriorityQueue]], [[Core.OrderedMap]], and [[Core.OrderedSet]],
reserving zero or an already available capacity leaves elements and storage intact.
[[Core.Array.reserve]] has a different, explicit zero-capacity contract: `reserve(0)`
releases its storage and removes all elements, just like [[Core.Array.free]].

## Building byte buffers

[[Core.ConcatBuffer]] owns a chain of byte buckets and supports a write cursor.
Writes overwrite existing bytes at that cursor and extend the buffer when needed.
[[Core.ConcatBuffer.reserveInPlace]] returns contiguous storage to fill directly;
crossing an existing bucket boundary merges the content and invalidates borrowed
positions and pointers. Save a [[Core.ConcatBufferPosition]] only while its bucket
storage remains valid.

`clear` retains the buckets for reuse; `release` frees them and leaves the buffer
reusable with the same allocator and bucket size. The buffer can be moved with
`#move`, but implicit copies are rejected. Moving an embedded first bucket also
invalidates positions borrowed from that header.

[[Core.ConcatBuffer.toArray]] copies all bytes into an independently owned array without
merging buckets or moving the cursor. Use it when an API needs one contiguous owned
block, such as an encoded image or video payload.

[[Core.ConcatBuffer.toString]] copies the content. [[Core.ConcatBuffer.moveToString]]
consumes a single heap bucket and returns an owned, null-terminated string; it copies
multiple active buckets or an embedded first bucket, leaving the buffer intact.
Use [[Core.ConcatBuffer.toSlice]] for a temporary borrow when one active bucket holds
the content. Its const overload exposes read-only bytes.
