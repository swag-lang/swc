#global fileprivate

// Real-life example: a heap-backed dynamic string that drives every
// lifecycle hook — opSet to build from a string literal, opPostCopy to
// deep-copy the owned buffer on assignment, opPostMove to fix up the
// destination after a move, opDrop to release the heap buffer, plus
// opIndex / opIndexSet / opAssign("+=") / opEquals for day-to-day use.

const MinCapacity = 8'u64

struct DynString
{
    data:     [*] u8
    count:    u64
    capacity: u64
}

// ---------------------------------------------------------------------------
// Internal helpers. These operate on raw storage and deliberately do NOT
// call any special operator: they are used from inside the methods below.
// ---------------------------------------------------------------------------

func reserve(s: *DynString, want: u64)
{
    if want <= s.capacity do
        return

    var newCap = s.capacity
    if newCap < MinCapacity do
        newCap = MinCapacity
    while newCap < want do
        newCap *= 2

    if s.data do
        s.data = cast([*] u8) @realloc(s.data, newCap)
    else do
        s.data = cast([*] u8) @alloc(newCap)
    s.capacity = newCap
}

func storeBytes(s: *DynString, src: const [*] u8, len: u64)
{
    reserve(s, len)
    for i in len do
        s.data[i] = src[i]
    s.count = len
}

func appendBytes(s: *DynString, src: const [*] u8, len: u64)
{
    reserve(s, s.count + len)
    for i in len do
        s.data[s.count + i] = src[i]
    s.count += len
}

// ---------------------------------------------------------------------------
// Struct special operators
// ---------------------------------------------------------------------------

impl DynString
{
    // Release the owned buffer. Called at end-of-scope and before copy-assign.
    mtd opDrop()
    {
        if .data
        {
            @free(.data)
            .data = null
        }
        .count = 0
        .capacity = 0
    }

    // Called on the destination right after a bytewise copy of the source.
    // The raw copy left both objects sharing the same buffer, so we clone it
    // here to restore the invariant that each DynString owns its data.
    mtd opPostCopy()
    {
        if .count == 0
        {
            .data = null
            .capacity = 0
            return
        }

        let oldData = .data
        .data = null
        .capacity = 0
        reserve(&me, .count)
        for i in .count do
            .data[i] = oldData[i]
    }

    // Called on the destination right after a bytewise move. The raw bytes
    // already describe a valid owning string, so nothing to fix up here.
    // The moved-from source is skipped by the drop machinery.
    mtd opPostMove()
    {
    }

    // Build from a string literal: `s = "hello"` when s is a DynString.
    mtd opSet(text: string)
    {
        .data = null
        .count = 0
        .capacity = 0

        let len = cast(u64) @countof(text)
        if len == 0 do
            return
        storeBytes(&me, cast(const [*] u8) @dataof(text), len)
    }

    // Read a byte: `let c = s[i]`
    mtd opIndex(index: u64) -> u8
    {
        @assert(index < .count)
        return .data[index]
    }

    // Write a byte: `s[i] = c`
    mtd opIndexSet(index: u64, value: u8)
    {
        @assert(index < .count)
        .data[index] = value
    }

    // Append: `s += "world"`
    #[Swag.Overload]
    mtd(op: string) opAssign(text: string)
    {
        #if op == "+="
        {
            let len = cast(u64) @countof(text)
            if len > 0 do
                appendBytes(&me, cast(const [*] u8) @dataof(text), len)
        }
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    // Append: `s += other`
    #[Swag.Overload]
    mtd(op: string) opAssign(other: const &DynString)
    {
        #if op == "+="
        {
            if other.count > 0 do
                appendBytes(&me, other.data, other.count)
        }
        #else do
            #error("unsupported opAssign op [[" ++ op ++ "]]")
    }

    // Byte-exact equality: `s == other`
    mtd opEquals(other: const &DynString) -> bool
    {
        if .count != other.count do
            return false
        for i in .count
        {
            if .data[i] != other.data[i] do
                return false
        }
        return true
    }
}

// ---------------------------------------------------------------------------
// Test: opSet builds, opDrop frees, content is reachable via .count / []
// ---------------------------------------------------------------------------

#test
{
    var s: DynString
    s = "hello"

    @assert(s.count == 5)
    @assert(s.capacity >= 5)
    @assert(s[0] == 'h''u8)
    @assert(s[4] == 'o''u8)
}

// ---------------------------------------------------------------------------
// Test: opPostCopy clones the buffer, so mutating one side leaves the
// other untouched. Both ends must free independently at scope exit.
// ---------------------------------------------------------------------------

#test
{
    var src: DynString
    src = "alpha"
    var dst: DynString
    dst = src                           // copy-assign: triggers opPostCopy on dst

    @assert(src.count == 5)
    @assert(dst.count == 5)
    @assert(src.data != dst.data)       // distinct heap buffers

    dst[0] = 'A''u8
    @assert(dst[0] == 'A''u8)
    @assert(src[0] == 'a''u8)           // original untouched
}

// ---------------------------------------------------------------------------
// Test: opPostMove transfers ownership; no double-free.
// ---------------------------------------------------------------------------

#test
{
    var src: DynString
    src = "transfer"
    var dst: DynString
    dst = #move src

    @assert(dst.count == 8)
    @assert(dst[0] == 't''u8)
    @assert(dst[7] == 'r''u8)

    // src was moved-from; it won't be opDrop'd at scope exit, so dst owns the
    // sole buffer. Rebind src to prove it is still a usable DynString.
    src = "reused"
    @assert(src.count == 6)
    @assert(src[0] == 'r''u8)
}

// ---------------------------------------------------------------------------
// Test: opIndex / opIndexSet — mutate bytes through indexing.
// ---------------------------------------------------------------------------

#test
{
    var s: DynString
    s = "abcdef"

    // Uppercase each byte via opIndex + opIndexSet
    for i in s.count
    {
        let c = s[i]
        s[i] = c - ('a''u8 - 'A''u8)
    }

    @assert(s.count == 6)
    @assert(s[0] == 'A''u8)
    @assert(s[1] == 'B''u8)
    @assert(s[5] == 'F''u8)
}

// ---------------------------------------------------------------------------
// Test: opAssign("+=") appending literals and other DynStrings, including
// growth past the initial capacity.
// ---------------------------------------------------------------------------

#test
{
    var s: DynString
    s = "foo"
    let startCap = s.capacity

    s += "-"
    s += "bar"
    @assert(s.count == 7)
    @assert(s[0] == 'f''u8)
    @assert(s[3] == '-''u8)
    @assert(s[6] == 'r''u8)

    // Append another DynString by const reference.
    var tail: DynString
    tail = "-baz"
    s += tail
    @assert(s.count == 11)
    @assert(s[7] == '-''u8)
    @assert(s[10] == 'z''u8)

    // Force at least one grow past the initial capacity.
    var wide: DynString
    wide = "x"
    for 40 do
        wide += "y"
    @assert(wide.count == 41)
    @assert(wide.capacity > startCap)
    @assert(wide[0] == 'x''u8)
    @assert(wide[40] == 'y''u8)
}

// ---------------------------------------------------------------------------
// Test: opEquals compares by content, independent of capacity / allocation.
// ---------------------------------------------------------------------------

#test
{
    var a: DynString
    a = "match"
    var b: DynString
    b += "ma"
    b += "tch"

    @assert(a == b)                     // same content, different allocations
    @assert(a.data != b.data)

    var c: DynString
    c = "MATCH"
    @assert(!(a == c))

    var d: DynString
    d = "matchx"
    @assert(!(a == d))
}

// ---------------------------------------------------------------------------
// Test: empty-string edge cases exercise the opSet / opPostCopy / opDrop
// paths with a zero-length buffer.
// ---------------------------------------------------------------------------

#test
{
    var empty: DynString
    empty = ""
    @assert(empty.count == 0)
    @assert(empty.data == null)

    var copy: DynString
    copy = empty                        // opPostCopy on empty payload
    @assert(copy.count == 0)
    @assert(copy.data == null)

    copy += "kick"
    @assert(copy.count == 4)
    @assert(empty.count == 0)
    @assert(copy[0] == 'k''u8)
}
