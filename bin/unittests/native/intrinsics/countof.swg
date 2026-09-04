#global private     //

// ============================================================
// Compile-time — enums
// ============================================================

enum Color { R, G, B }
#assert(Color.count == 3)
#assert(Color.count != 2)

enum Direction { N, S, E, W }
#assert(Direction.count == 4)

enum Single { Only }
#assert(Single.count == 1)

struct CountedRuntime
{
    count: u64
}

struct ZeroSized {}

enum RefCountKind
{
    A
    B
    C
    D
}

#[Swag.Strict]
alias CountOfStrictU32    = u32

#[Swag.Strict]
alias CountOfStrictSlice  = [..] u8

#[Swag.Strict]
alias CountOfStrictString = string

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

#assert(("ABCDE").count == 5)
#assert(("").count == 0)
#assert(("X").count == 1)

const StrConst = "XYZ"
#assert(StrConst.count == 3)

const EmptyConst = ""
#assert(EmptyConst.count == 0)

// ============================================================
// Compile-time — integer passthrough
// ============================================================

#test
{
    const a = (3).count
    const b = (0).count
    const c = (100).count
    const d = (3's8).count
    const e = (4's32).count
    const f = (5's64).count
    #assert(a == 3)
    #assert(b == 0)
    #assert(c == 100)
    #assert(#typeof(d) == s8)
    #assert(#typeof(e) == s32)
    #assert(#typeof(f) == s64)
    #assert(d == 3's8)
    #assert(e == 4's32)
    #assert(f == 5's64)
    Swag.assert(a == 3)
    Swag.assert(b == 0)
    Swag.assert(c == 100)
    Swag.assert(d == 3's8)
    Swag.assert(e == 4's32)
    Swag.assert(f == 5's64)
}

#test
{
    var runtime = cast(CountOfStrictU32) 7'u32
    const constant = (cast(CountOfStrictU32) 5'u32).count
    let value = runtime.count

    #assert(#typeof(constant) == CountOfStrictU32)
    #assert(#typeof(value) == CountOfStrictU32)
    Swag.assert(constant == cast(CountOfStrictU32) 5'u32)
    Swag.assert(value == cast(CountOfStrictU32) 7'u32)
}

// ============================================================
// Runtime — string and cstring
// ============================================================

namespace NS {}

#test
{
    var a: string?
    var b = a.count
    #assert(#typeof(b) == u64)

    var cs: cstring?
    var csc = cs.count
    #assert(#typeof(csc) == u64)

    Swag.assert(b == 0)
    Swag.assert(csc == 0)
}

#test
{
    var a: string = "hello"
    Swag.assert(a.count == 5)

    var b: string = ""
    Swag.assert(b.count == 0)

    var c: string = "X"
    Swag.assert(c.count == 1)
}

#test
{
    var text = cast(CountOfStrictString) "hello"
    Swag.assert(text.count == 5)

    var data: [3] u8 = [1, 2, 3]
    var slice        = cast(CountOfStrictSlice) data
    Swag.assert(slice.count == 3)
}

// ============================================================
// Compile-time — fixed arrays
// ============================================================

#test
{
    var c: [4, 10] s32
    const d = c.count
    #assert(d == 40)
    Swag.assert(d == 40)
}

#test
{
    var a: [2, 3, 4] u8
    const b = a.count
    #assert(b == 24)
    Swag.assert(b == 24)
}

#test
{
    var a: [7] bool
    const b = a.count
    #assert(b == 7)
    Swag.assert(b == 7)
}

#test
{
    var a: [1] u64
    const b = a.count
    #assert(b == 1)
    Swag.assert(b == 1)
}

#test
{
    let value0 = CountedRuntime{count: 7}
    let value1 = CountedRuntime{count: 0}
    const c0 = value0.count
    const c1 = value1.count
    #assert(c0 == 7)
    #assert(c1 == 0)
    Swag.assert(c0 == 7)
    Swag.assert(c1 == 0)
}

#test
{
    var values: [3] ZeroSized
    let slice = cast([..] ZeroSized) values
    let count = slice.count
    #assert(#typeof(count) == u64)
    Swag.assert(count == 3)
}

// ============================================================
// Runtime — slices
// ============================================================

#test
{
    var buf: [5] s32 = [10, 20, 30, 40, 50]
    let sl           = Swag.makeSlice(&buf[0], 3)
    Swag.assert(sl.count == 3)

    let sl2 = Swag.makeSlice(&buf[0], 5)
    Swag.assert(sl2.count == 5)

    let sl3 = Swag.makeSlice(&buf[0], 0)
    Swag.assert(sl3.count == 0)
}

func countStringRef(value: *string)->u64
{
    return (value[]).count
}

func countCStringRef(value: *cstring)->u64
{
    return (value[]).count
}

func countSliceRef(value: [..] u8)->u64
{
    return value.count
}

func countUnsignedRef(value: *u32)->u32
{
    return (value[]).count
}

func countSignedRef(value: *s32)->s32
{
    return (value[]).count
}

func countEnumRef(value: *RefCountKind)->u64
{
    return (value[]).count
}

func countSpecOpRef(value: RefCountedRuntime)->u64
{
    return value.count
}

func loopStringRef(value: string)->u64
{
    var count: u64 = 0
    for value do
        count += 1
    return count
}

func loopCStringRef(value: *cstring)->u64
{
    var count: u64 = 0
    for value[] do
        count += 1
    return count
}

func loopSliceRef(value: [..] u8)->u64
{
    var count: u64 = 0
    for value do
        count += 1
    return count
}

func loopUnsignedRef(value: *u32)->u32
{
    var count: u32 = 0
    for value[] do
        count += 1
    return count
}

func loopSignedRef(value: *s32)->s32
{
    var count: s32 = 0
    for value[] do
        count += 1
    return count
}

#test
{
    var text             = "hello"
    var textRef: *string = &text
    Swag.assert((textRef[]).count == 5)
    Swag.assert(countStringRef(textRef) == 5)
    Swag.assert(loopStringRef(textRef[]) == 5)
}

#test
{
    var data:    [5] u8   = ['a'u8, 'b'u8, 'c'u8, 'd'u8, 0]
    var cstr:    cstring  = cast(cstring) &data[0]
    var cstrRef: *cstring = &cstr
    Swag.assert((cstrRef[]).count == 4)
    Swag.assert(countCStringRef(cstrRef) == 4)
    Swag.assert(loopCStringRef(cstrRef) == 4)
}

#test
{
    var array:    [2, 3] u8
    var arrayRef: *[2, 3] u8 = &array
    Swag.assert((arrayRef[]).count == 6)

    var flat:     [6] u8         = [1, 2, 3, 4, 5, 6]
    let slice                    = cast([..] u8) flat
    var sliceRef: const *[..] u8 = &slice
    Swag.assert((sliceRef[]).count == 6)
    Swag.assert(countSliceRef(sliceRef[]) == 6)
    Swag.assert(loopSliceRef(sliceRef[]) == 6)
}

#test
{
    var number:    u32  = 7
    var numberRef: *u32 = &number
    Swag.assert(#typeof((numberRef[]).count) == u32)
    Swag.assert((numberRef[]).count == 7)
    Swag.assert(countUnsignedRef(numberRef) == 7)
    Swag.assert(loopUnsignedRef(numberRef) == 7)
}

#test
{
    var number:    s32  = 7
    var numberRef: *s32 = &number
    Swag.assert(#typeof((numberRef[]).count) == s32)
    Swag.assert((numberRef[]).count == 7)
    Swag.assert(countSignedRef(numberRef) == 7)
    Swag.assert(loopSignedRef(numberRef) == 7)
}

#test
{
    var kind = RefCountKind.C
    var kindRef: *RefCountKind = &kind
    Swag.assert((kindRef[]).count == 4)
    Swag.assert(countEnumRef(kindRef) == 4)

    let counted = RefCountedRuntime{count: 11}
    let countedRef: const *RefCountedRuntime = &counted
    Swag.assert((countedRef[]).count == 11)
    Swag.assert(countSpecOpRef(countedRef) == 11)
}

// A '.count' that resolves 'opCount' lowers to a call, and a truthiness context wraps
// that node in an implicit cast. Code generation must keep resolving the wrapped node to
// its cast: losing the link left the enclosing 'if' with no condition to branch on.
#[Swag.NoInline]
func countedRuntimeIsNotEmpty(value: CountedRuntime)->s32
{
    var result = 0's32
    if value.count do
        result = 1
    return result
}

#test
{
    var filled: CountedRuntime
    filled.count = 7
    var empty: CountedRuntime
    empty.count = 0

    Swag.assert(countedRuntimeIsNotEmpty(filled) == 1)
    Swag.assert(countedRuntimeIsNotEmpty(empty) == 0)
}
