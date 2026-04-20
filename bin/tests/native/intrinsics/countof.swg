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

enum RefCountKind
{
    A
    B
    C
    D
}

struct RefCountedRuntime
{
    count: u64
}

impl CountedRuntime
{
    mtd opCount() => me.count
}

impl RefCountedRuntime
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
    const d = @countof(3's8)
    const e = @countof(4's32)
    const f = @countof(5's64)
    #assert(a == 3)
    #assert(b == 0)
    #assert(c == 100)
    #assert(#typeof(d) == s8)
    #assert(#typeof(e) == s32)
    #assert(#typeof(f) == s64)
    #assert(d == 3's8)
    #assert(e == 4's32)
    #assert(f == 5's64)
    @assert(a == 3)
    @assert(b == 0)
    @assert(c == 100)
    @assert(d == 3's8)
    @assert(e == 4's32)
    @assert(f == 5's64)
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

func countStringRef(value: &string)->u64
{
    return @countof(value)
}

func countCStringRef(value: &cstring)->u64
{
    return @countof(value)
}

func countSliceRef(value: const &[..] u8)->u64
{
    return @countof(value)
}

func countUnsignedRef(value: &u32)->u32
{
    return @countof(value)
}

func countSignedRef(value: &s32)->s32
{
    return @countof(value)
}

func countEnumRef(value: &RefCountKind)->u64
{
    return @countof(value)
}

func countSpecOpRef(value: const &RefCountedRuntime)->u64
{
    return @countof(value)
}

func loopStringRef(value: const &string)->u64
{
    var count: u64 = 0
    for value do
        count += 1
    return count
}

func loopCStringRef(value: &cstring)->u64
{
    var count: u64 = 0
    for value do
        count += 1
    return count
}

func loopSliceRef(value: const &[..] u8)->u64
{
    var count: u64 = 0
    for value do
        count += 1
    return count
}

func loopUnsignedRef(value: &u32)->u32
{
    var count: u32 = 0
    for value do
        count += 1
    return count
}

func loopSignedRef(value: &s32)->s32
{
    var count: s32 = 0
    for value do
        count += 1
    return count
}

#test
{
    var text = "hello"
    var textRef: &string = &text
    @assert(@countof(textRef) == 5)
    @assert(countStringRef(textRef) == 5)
    @assert(loopStringRef(textRef) == 5)
}

#test
{
    var cstr: cstring = cast(cstring) @dataof("abcd")
    var cstrRef: &cstring = &cstr
    @assert(@countof(cstrRef) == 4)
    @assert(countCStringRef(cstrRef) == 4)
    @assert(loopCStringRef(cstrRef) == 4)
}

#test
{
    var array: [2, 3] u8
    var arrayRef: &[2, 3] u8 = &array
    @assert(@countof(arrayRef) == 6)

    var flat: [6] u8 = [1, 2, 3, 4, 5, 6]
    let slice = cast([..] u8) flat
    var sliceRef: const &[..] u8 = &slice
    @assert(@countof(sliceRef) == 6)
    @assert(countSliceRef(sliceRef) == 6)
    @assert(loopSliceRef(sliceRef) == 6)
}

#test
{
    var number: u32 = 7
    var numberRef: &u32 = &number
    @assert(#typeof(@countof(numberRef)) == u32)
    @assert(@countof(numberRef) == 7)
    @assert(countUnsignedRef(numberRef) == 7)
    @assert(loopUnsignedRef(numberRef) == 7)
}

#test
{
    var number: s32 = 7
    var numberRef: &s32 = &number
    @assert(#typeof(@countof(numberRef)) == s32)
    @assert(@countof(numberRef) == 7)
    @assert(countSignedRef(numberRef) == 7)
    @assert(loopSignedRef(numberRef) == 7)
}

#test
{
    var kind = RefCountKind.C
    var kindRef: &RefCountKind = &kind
    @assert(@countof(kindRef) == 4)
    @assert(countEnumRef(kindRef) == 4)

    let counted = RefCountedRuntime{count: 11}
    let countedRef: const &RefCountedRuntime = &counted
    @assert(@countof(countedRef) == 11)
    @assert(countSpecOpRef(countedRef) == 11)
}
