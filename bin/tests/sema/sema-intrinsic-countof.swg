#global internal

enum A { R, G, B }
#assert(@countof(A) == 3)
#assert(@countof(A) != 2)

#assert(@countof("ABCDE") == 5)
const B = "XYZ"
#assert(@countof(B) == 3)

#test
{
    const a = @countof(3)
    #assert(a == 3)
    #assert(#typeof(a) == u32)

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

    var c: [4, 10] s32
    const d = @countof(c)
    #assert(d == 40)
}
