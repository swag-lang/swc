#global fileprivate //

// ============================================================
// Compile-time — enums
// ============================================================

enum Color { R, G, B }
#assert(@countof(Color) == 3)
#assert(@countof(Color) != 2)

enum Direction { N, S, E, W }
#assert(@countof(Direction) == 4)

enum Single { Only }
#assert(@countof(Single) == 1)

struct CountedRuntime
{
    count: u64
}

struct ZeroSized
{
}

impl CountedRuntime
{
    mtd opCount() => me.count
}

// ============================================================
// Compile-time — string literals
// ============================================================

#assert(@countof("ABCDE") == 5)
#assert(@countof("") == 0)
#assert(@countof("X") == 1)

const StrConst = "XYZ"
#assert(@countof(StrConst) == 3)

const EmptyConst = ""
#assert(@countof(EmptyConst) == 0)

// ============================================================
// Compile-time — integer passthrough
// ============================================================

#test
{
    const a = @countof(3)
    const b = @countof(0)
    const c = @countof(100)
    #assert(a == 3)
    #assert(b == 0)
    #assert(c == 100)
    @assert(a == 3)
    @assert(b == 0)
    @assert(c == 100)
}

// ============================================================
// Runtime — string and cstring
// ============================================================

namespace NS {}

#test
{
    var a: string
    var b = @countof(a)
    #assert(#typeof(b) == u64)

    var cs: cstring
    var csc = @countof(cs)
    #assert(#typeof(csc) == u64)

    @assert(b == 0)
    @assert(csc == 0)
}

#test
{
    var a: string = "hello"
    @assert(@countof(a) == 5)

    var b: string = ""
    @assert(@countof(b) == 0)

    var c: string = "X"
    @assert(@countof(c) == 1)
}

// ============================================================
// Compile-time — fixed arrays
// ============================================================

#test
{
    var c: [4, 10] s32
    const d = @countof(c)
    #assert(d == 40)
    @assert(d == 40)
}

#test
{
    var a: [2, 3, 4] u8
    const b = @countof(a)
    #assert(b == 24)
    @assert(b == 24)
}

#test
{
    var a: [7] bool
    const b = @countof(a)
    #assert(b == 7)
    @assert(b == 7)
}

#test
{
    var a: [1] u64
    const b = @countof(a)
    #assert(b == 1)
    @assert(b == 1)
}

#test
{
    let value0 = CountedRuntime{count: 7}
    let value1 = CountedRuntime{count: 0}
    const c0 = @countof(value0)
    const c1 = @countof(value1)
    #assert(c0 == 7)
    #assert(c1 == 0)
    @assert(c0 == 7)
    @assert(c1 == 0)
}

#test
{
    var values: [3] ZeroSized
    let slice = cast([..] ZeroSized) values
    let count = @countof(slice)
    #assert(#typeof(count) == u64)
    @assert(count == 3)
}

// ============================================================
// Runtime — slices
// ============================================================

#test
{
    var buf: [5] s32 = [10, 20, 30, 40, 50]
    let sl = @mkslice(&buf[0], 3)
    @assert(@countof(sl) == 3)

    let sl2 = @mkslice(&buf[0], 5)
    @assert(@countof(sl2) == 5)

    let sl3 = @mkslice(&buf[0], 0)
    @assert(@countof(sl3) == 0)
}
