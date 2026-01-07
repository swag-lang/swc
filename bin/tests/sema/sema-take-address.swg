#global internal

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v: *AA = &st
    #assert(#typeof(v) == *AA)
    var v1 = &AA // swc-expected-error {{sema_err_not_value_expr}}
}

#test
{
    let A = 10's32
    let PA = &A
    #assert(#typeof(PA) == const *s32)
    let PB = &0 // swc-expected-error {{sema_err_take_address_constant}}
}

#test
{
    var x: [4] s32
    var px = &x
    #assert(#typeof(px) == [*][4] s32)
    #assert(#typeof(px) == *[4] s32) // swc-expected-error {{sema_err_compiler_assert}}
}

#test
{
    var buf: [4] s32
    var a = &buf
    var c = a[0]
    #print(#typeof(c))
}