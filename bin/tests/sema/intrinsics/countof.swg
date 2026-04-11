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

impl CountedBySpecOp
{
    mtd opCount() => 9'u64
}

#assert(@countof(CountedBySpecOp{}) == 9)

const ZERO_SIZED_VALUES: [3] ZeroSized = [{}, {}, {}]
const ZERO_SIZED_SLICE = cast([..] ZeroSized) ZERO_SIZED_VALUES
#assert(@countof(ZERO_SIZED_SLICE) == 3)

#test
{
    const a = @countof(3)
    #assert(a == 3)
    const b = @countof(-1) // swc-expected-error {{sema_err_count_negative}}
}

namespace NS {}
#assert(@countof(NS) == 3) // swc-expected-error {{sema_err_not_value_expr}}
#assert(@countof(true) == 1) // swc-expected-error {{sema_err_invalid_countof_type}}

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
