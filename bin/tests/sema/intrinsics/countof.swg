#global fileprivate

enum A { R, G, B }
#assert(@countof(A) == 3)
#assert(@countof(A) != 2)

#assert(@countof("ABCDE") == 5)
const B = "XYZ"
#assert(@countof(B) == 3)

struct CountedBySpecOp
{
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

struct RefCountedBySpecOp
{
    count: u64
}

impl CountedBySpecOp
{
    mtd opCount() => 9'u64
}

impl RefCountedBySpecOp
{
    mtd opCount() => me.count
}

#assert(@countof(CountedBySpecOp{}) == 9)

const ZERO_SIZED_VALUES: [3] ZeroSized = [{}, {}, {}]
const ZERO_SIZED_SLICE = cast([..] ZeroSized) ZERO_SIZED_VALUES
#assert(@countof(ZERO_SIZED_SLICE) == 3)

namespace NS {}

#test
{
    var a: string
    var b = @countof(a)
    #assert(#typeof(b) == u64)

    var cs: cstring
    var csc = @countof(cs)
    #assert(#typeof(csc) == u64)

    var c: [4, 10] s32
    const d = @countof(c)
    #assert(d == 40)
}

#test
{
    var a: [2, 3, 4] u8
    const b = @countof(a)
    #assert(b == 24)
}

#test
{
    var a: [7] bool
    const b = @countof(a)
    #assert(b == 7)
}

#test
{
    let value = CountedBySpecOp{}
    const count = @countof(value)
    #assert(#typeof(count) == u64)
    #assert(count == 9)
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

func countEnumRef(value: &RefCountKind)->u64
{
    return @countof(value)
}

func countSpecOpRef(value: const &RefCountedBySpecOp)->u64
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

#test
{
    var text = "hello"
    var textRef: &string = &text
    #assert(#typeof(@countof(textRef)) == u64)
    #assert(#typeof(countStringRef(textRef)) == u64)
    #assert(#typeof(loopStringRef(textRef)) == u64)

    var cstr: cstring = cast(cstring) @dataof("abc")
    var cstrRef: &cstring = &cstr
    #assert(#typeof(@countof(cstrRef)) == u64)
    #assert(#typeof(countCStringRef(cstrRef)) == u64)
    #assert(#typeof(loopCStringRef(cstrRef)) == u64)

    var array: [2, 3] u8
    var arrayRef: &[2, 3] u8 = &array
    #assert(@countof(arrayRef) == 6)

    var flat: [6] u8
    let slice = cast([..] u8) flat
    var sliceRef: const &[..] u8 = &slice
    #assert(#typeof(@countof(sliceRef)) == u64)
    #assert(#typeof(countSliceRef(sliceRef)) == u64)
    #assert(#typeof(loopSliceRef(sliceRef)) == u64)

    var number: u32 = 4
    var numberRef: &u32 = &number
    #assert(#typeof(@countof(numberRef)) == u32)
    #assert(#typeof(countUnsignedRef(numberRef)) == u32)
    #assert(#typeof(loopUnsignedRef(numberRef)) == u32)

    var kind = RefCountKind.B
    var kindRef: &RefCountKind = &kind
    #assert(@countof(kindRef) == 4)
    #assert(#typeof(countEnumRef(kindRef)) == u64)

    let spec = RefCountedBySpecOp{count: 11}
    let specRef: const &RefCountedBySpecOp = &spec
    #assert(@countof(specRef) == 11)
    #assert(#typeof(countSpecOpRef(specRef)) == u64)
}
