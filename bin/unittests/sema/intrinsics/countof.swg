#global private

enum A { R, G, B }
#assert(A.count == 3)
#assert(A.count != 2)

#assert(("ABCDE").count == 5)
const B = "XYZ"
#assert(B.count == 3)

struct CountedBySpecOp {}

struct ZeroSized {}

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

#assert((CountedBySpecOp{}).count == 9)

const ZERO_SIZED_VALUES: [3] ZeroSized        = [{}, {}, {}]
const ZERO_SIZED_SLICE:  const [..] ZeroSized = cast(const [..] ZeroSized) ZERO_SIZED_VALUES
#assert(ZERO_SIZED_SLICE.count == 3)

namespace NS {}

func semaTest001()
{
    var a: #null string
    var b = a.count
    #assert(#typeof(b) == u64)

    var cs: #null cstring
    var csc = cs.count
    #assert(#typeof(csc) == u64)

    var c: [4, 10] s32
    const d = c.count
    #assert(d == 40)
}

func semaTest002()
{
    var a: [2, 3, 4] u8
    const b = a.count
    #assert(b == 24)
}

func semaTest003()
{
    var a: [7] bool
    const b = a.count
    #assert(b == 7)
}

func semaTest004()
{
    let value = CountedBySpecOp{}
    const count = value.count
    #assert(#typeof(count) == u64)
    #assert(count == 9)
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

func countEnumRef(value: *RefCountKind)->u64
{
    return (value[]).count
}

func countSpecOpRef(value: RefCountedBySpecOp)->u64
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

func semaTest005()
{
    var text             = "hello"
    var textRef: *string = &text
    #assert(#typeof((textRef[]).count) == u64)
    #assert(#typeof(countStringRef(textRef)) == u64)
    #assert(#typeof(loopStringRef(textRef[])) == u64)

    var cstrData: [4] u8   = ['a'u8, 'b'u8, 'c'u8, 0]
    var cstr:     cstring  = cast(cstring) &cstrData[0]
    var cstrRef:  *cstring = &cstr
    #assert(#typeof((cstrRef[]).count) == u64)
    #assert(#typeof(countCStringRef(cstrRef)) == u64)
    #assert(#typeof(loopCStringRef(cstrRef)) == u64)

    var array:    [2, 3] u8
    var arrayRef: *[2, 3] u8 = &array
    #assert((arrayRef[]).count == 6)

    var flat:     [6] u8
    let slice = cast([..] u8) flat
    var sliceRef: const *[..] u8 = &slice
    #assert(#typeof((sliceRef[]).count) == u64)
    #assert(#typeof(countSliceRef(sliceRef[])) == u64)
    #assert(#typeof(loopSliceRef(sliceRef[])) == u64)

    var number:    u32  = 4
    var numberRef: *u32 = &number
    #assert(#typeof((numberRef[]).count) == u32)
    #assert(#typeof(countUnsignedRef(numberRef)) == u32)
    #assert(#typeof(loopUnsignedRef(numberRef)) == u32)

    var kind = RefCountKind.B
    var kindRef: *RefCountKind = &kind
    #assert((kindRef[]).count == 4)
    #assert(#typeof(countEnumRef(kindRef)) == u64)

    let spec = RefCountedBySpecOp{count: 11}
    let specRef: const *RefCountedBySpecOp = &spec
    #assert((specRef[]).count == 11)
    #assert(#typeof(countSpecOpRef(specRef[])) == u64)
}
