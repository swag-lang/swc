#global fileprivate

// Real-life example: a small-vector with inline storage that exercises every
// lifecycle hook in a non-trivial way. When the element count fits in a fixed
// inline buffer the data lives inside the struct itself; when it overflows,
// a heap buffer is allocated. A `ptr` field always points at the active
// storage, which means:
//
//   opPostCopy  -- inline: fix ptr to own inline buffer
//                  heap:   deep-copy the heap buffer, fix ptr
//   opPostMove  -- inline: fix ptr to own inline buffer
//                  heap:   ptr already valid, nothing to do
//   opDrop      -- heap:   free the heap allocation
//                  inline: nothing to free

const InlineCap = 4'u64

struct SmallVec
{
    inline:   [InlineCap] s32
    ptr:      [*] s32
    count:    u64
    capacity: u64
}

impl SmallVec
{
    mtd isInline() -> bool
    {
        return .capacity <= InlineCap
    }

    mtd init()
    {
        .ptr = cast([*] s32) &.inline[0]
        .count = 0
        .capacity = InlineCap
    }

    mtd growTo(want: u64)
    {
        if want <= .capacity do
            return

        var newCap = .capacity
        while newCap < want do
            newCap *= 2

        let newBuf = cast([*] s32) @alloc(newCap * #sizeof(s32))
        for i in .count do
            newBuf[i] = .ptr[i]

        if !.isInline() do
            @free(.ptr)

        .ptr = newBuf
        .capacity = newCap
    }

    mtd push(value: s32)
    {
        .growTo(.count + 1)
        .ptr[.count] = value
        .count += 1
    }

    mtd at(i: u64) -> s32
    {
        @assert(i < .count)
        return .ptr[i]
    }

    // -----------------------------------------------------------------------
    // Lifecycle operators
    // -----------------------------------------------------------------------

    mtd opDrop()
    {
        // Only free when data lives on the heap.
        if !.isInline() do
            @free(.ptr)
        .ptr = null
        .count = 0
        .capacity = 0
    }

    mtd opPostCopy()
    {
        // After the bytewise copy, .ptr points into the SOURCE's inline
        // storage (or at the shared heap buffer). Fix it up.
        if .isInline()
        {
            // Data fits inline -- just redirect ptr to our own buffer.
            .ptr = cast([*] s32) &.inline[0]
        }
        else
        {
            // Heap path: allocate a fresh buffer and copy the elements.
            let oldPtr = .ptr
            .ptr = cast([*] s32) @alloc(.capacity * #sizeof(s32))
            for i in .count do
                .ptr[i] = oldPtr[i]
        }
    }

    mtd opPostMove()
    {
        // After the bytewise move, the source is dead. If data was inline,
        // .ptr still references the source's inline storage -- fix it.
        if .isInline() do
            .ptr = cast([*] s32) &.inline[0]
        // Heap: ptr already points at the heap buffer, nothing to fix.
    }

    // Build from an initializer count: `var v: SmallVec = 3` fills with zeros.
    mtd opAffect(n: u64)
    {
        .init()
        for n do
            .push(0)
    }
}

// ---------------------------------------------------------------------------
// Test: basic inline storage, push and read
// ---------------------------------------------------------------------------

#test
{
    var v: SmallVec
    v.init()

    v.push(10)
    v.push(20)
    v.push(30)

    @assert(v.count == 3)
    @assert(v.isInline())
    @assert(v.at(0) == 10)
    @assert(v.at(1) == 20)
    @assert(v.at(2) == 30)
}

// ---------------------------------------------------------------------------
// Test: push beyond inline capacity triggers heap allocation
// ---------------------------------------------------------------------------

#test
{
    var v: SmallVec
    v.init()

    for i in 8'u64 do
        v.push(cast(s32) i * 7)

    @assert(v.count == 8)
    @assert(!v.isInline())
    @assert(v.capacity >= 8)
    @assert(v.at(0) == 0)
    @assert(v.at(7) == 49)
}

// ---------------------------------------------------------------------------
// Test: opPostCopy with inline data -- copies content, independent buffers
// ---------------------------------------------------------------------------

#test
{
    var src: SmallVec
    src.init()
    src.push(1)
    src.push(2)
    src.push(3)

    var dst: SmallVec
    dst.init()
    dst = src

    @assert(dst.count == 3)
    @assert(dst.isInline())
    @assert(dst.at(0) == 1)
    @assert(dst.at(2) == 3)

    // Mutate dst -- src must be unaffected.
    dst.ptr[0] = 99
    @assert(src.at(0) == 1)
    @assert(dst.at(0) == 99)
}

// ---------------------------------------------------------------------------
// Test: opPostCopy with heap data -- deep-copies the heap buffer
// ---------------------------------------------------------------------------

#test
{
    var src: SmallVec
    src.init()
    for i in 6'u64 do
        src.push(cast(s32) i + 100)

    @assert(!src.isInline())

    var dst: SmallVec
    dst.init()
    dst = src

    @assert(dst.count == 6)
    @assert(!dst.isInline())
    @assert(dst.ptr != src.ptr)

    @assert(dst.at(0) == 100)
    @assert(dst.at(5) == 105)

    // Mutate dst -- src stays intact.
    dst.ptr[0] = -1
    @assert(src.at(0) == 100)
    @assert(dst.at(0) == -1)
}

// ---------------------------------------------------------------------------
// Test: opPostMove with inline data -- ptr must be fixed up
// ---------------------------------------------------------------------------

#test
{
    var src: SmallVec
    src.init()
    src.push(7)
    src.push(8)

    @assert(src.isInline())

    var dst: SmallVec
    dst.init()
    dst = #move src

    @assert(dst.count == 2)
    @assert(dst.isInline())
    @assert(dst.at(0) == 7)
    @assert(dst.at(1) == 8)

    // Reuse the moved-from source.
    src.init()
    src.push(42)
    @assert(src.count == 1)
    @assert(src.at(0) == 42)
}

// ---------------------------------------------------------------------------
// Test: opPostMove with heap data -- ptr is already valid
// ---------------------------------------------------------------------------

#test
{
    var src: SmallVec
    src.init()
    for i in 6'u64 do
        src.push(cast(s32) i)

    @assert(!src.isInline())
    let heapPtr = src.ptr

    var dst: SmallVec
    dst.init()
    dst = #move src

    @assert(dst.count == 6)
    @assert(!dst.isInline())
    @assert(dst.ptr == heapPtr)
    @assert(dst.at(5) == 5)
}

// ---------------------------------------------------------------------------
// Test: chain of copies and moves -- every hook fires correctly
// ---------------------------------------------------------------------------

#test
{
    var a: SmallVec
    a.init()
    a.push(1)
    a.push(2)
    a.push(3)
    a.push(4)

    @assert(a.isInline())

    // Copy a -> b  (inline opPostCopy)
    var b: SmallVec
    b.init()
    b = a

    // Push b past inline cap -> heap
    b.push(5)
    b.push(6)
    @assert(!b.isInline())

    // Copy b -> c  (heap opPostCopy)
    var c: SmallVec
    c.init()
    c = b

    @assert(c.count == 6)
    @assert(c.ptr != b.ptr)
    @assert(c.at(0) == 1)
    @assert(c.at(5) == 6)

    // Move c -> d  (heap opPostMove)
    var d: SmallVec
    d.init()
    d = #move c

    @assert(d.count == 6)
    @assert(!d.isInline())
    @assert(d.at(3) == 4)

    // Move a -> e  (inline opPostMove)
    var e: SmallVec
    e.init()
    e = #move a

    @assert(e.count == 4)
    @assert(e.isInline())
    @assert(e.at(0) == 1)
    @assert(e.at(3) == 4)

    // All variables drop at end-of-scope: d frees heap, e frees nothing (inline).
}

// ---------------------------------------------------------------------------
// Test: copy then grow -- the copy starts inline but transitions to heap
// ---------------------------------------------------------------------------

#test
{
    var src: SmallVec
    src.init()
    src.push(10)
    src.push(20)

    var dst: SmallVec
    dst.init()
    dst = src

    @assert(dst.isInline())

    // Grow dst past inline cap.
    dst.push(30)
    dst.push(40)
    dst.push(50)
    @assert(!dst.isInline())
    @assert(dst.count == 5)

    // src still inline and untouched.
    @assert(src.isInline())
    @assert(src.count == 2)
    @assert(src.at(0) == 10)

    @assert(dst.at(4) == 50)
}

// ---------------------------------------------------------------------------
// Test: empty vec copy and move -- edge case with zero elements
// ---------------------------------------------------------------------------

#test
{
    var empty: SmallVec
    empty.init()

    var cpy: SmallVec
    cpy.init()
    cpy = empty
    @assert(cpy.count == 0)
    @assert(cpy.isInline())

    var moved: SmallVec
    moved.init()
    moved = #move empty
    @assert(moved.count == 0)
    @assert(moved.isInline())

    // Populate the moved-from variable, then copy it.
    empty.init()
    empty.push(77)
    cpy = empty
    @assert(cpy.at(0) == 77)
}

// ---------------------------------------------------------------------------
// Test: overwrite via copy -- opDrop fires on destination before opPostCopy
// ---------------------------------------------------------------------------

#test
{
    var dst: SmallVec
    dst.init()
    for i in 6'u64 do
        dst.push(cast(s32) i)
    @assert(!dst.isInline())

    // Copy a small vec into dst. The old heap buffer must be freed (opDrop)
    // before the new inline data is post-copied in.
    var src: SmallVec
    src.init()
    src.push(99)

    dst = src

    @assert(dst.count == 1)
    @assert(dst.isInline())
    @assert(dst.at(0) == 99)
}

// ---------------------------------------------------------------------------
// Test: overwrite via move -- opDrop fires on destination before opPostMove
// ---------------------------------------------------------------------------

#test
{
    var dst: SmallVec
    dst.init()
    for i in 8'u64 do
        dst.push(cast(s32) i * 3)
    @assert(!dst.isInline())

    var src: SmallVec
    src.init()
    src.push(42)
    src.push(43)

    dst = #move src

    @assert(dst.count == 2)
    @assert(dst.isInline())
    @assert(dst.at(0) == 42)
    @assert(dst.at(1) == 43)
}

// ---------------------------------------------------------------------------
// Test: struct containing SmallVec -- lifecycle propagates through nesting
// ---------------------------------------------------------------------------

struct Pair
{
    left:  SmallVec
    right: SmallVec
}

#test
{
    var p: Pair
    p.left.init()
    p.right.init()

    p.left.push(1)
    p.left.push(2)
    for i in 6'u64 do
        p.right.push(cast(s32) i)

    @assert(p.left.isInline())
    @assert(!p.right.isInline())

    // Copy the whole pair -- both SmallVecs get opPostCopy'd.
    var q: Pair
    q.left.init()
    q.right.init()
    q = p

    @assert(q.left.count == 2)
    @assert(q.right.count == 6)
    @assert(q.right.ptr != p.right.ptr)
    @assert(q.left.at(0) == 1)
    @assert(q.right.at(5) == 5)

    // Move the pair -- both SmallVecs get opPostMove'd.
    var r: Pair
    r.left.init()
    r.right.init()
    r = #move p

    @assert(r.left.count == 2)
    @assert(r.right.count == 6)
    @assert(r.left.at(1) == 2)
    @assert(r.right.at(0) == 0)
}
