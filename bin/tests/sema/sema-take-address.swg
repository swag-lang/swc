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
    struct AA { x: s32 }
    var x = 0
    var y = &(x + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    struct AA { x: s32 }
    var st: AA
    var z = &st.x
    var w = &(st.x + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var x: s32
    var px = &x
    #assert(#typeof(px) == *s32)
}

#test
{
    var x: s32
    var px = &x
    var ppx = &px
    #assert(#typeof(ppx) == **s32)
}

#test
{
    var x: s32
    var p = &x
    var q = &(&x) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    let A = 10's32
    let PA = &A
    let PB = &(A + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var a: [4] s32
    var p = &a[0]
    #assert(#typeof(p) == *s32)
}

#test
{
    var a: [4] s32
    var p = &(a[0] + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    struct B { y: s32 }
    struct C { b: B }
    var c: C
    var p = &c.b.y
    #assert(#typeof(p) == *s32)
    var q = &(c.b.y + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    struct AA { x: s32 }
    var st: AA
    var p1 = &st
    #assert(#typeof(p1) == *AA)
}

#test
{
    var x: s32
    var y: s32
    var px = &x
    var py = &y
    px = py
    #assert(#typeof(px) == *s32)
    #assert(#typeof(py) == *s32)
}

#test
{
    let A = 10's32
    let B = 20's32
    let PA = &A
    let PB = &B
    #assert(#typeof(PA) == const *s32)
    #assert(#typeof(PB) == const *s32)
}

#test
{
    var x: s32
    var y: s32
    var px = &x
    var py = &y
    var ppx = &px
    var ppy = &py
    #assert(#typeof(ppx) == **s32)
    #assert(#typeof(ppy) == **s32)
}

#test
{
    var x: s32
    var y = x
    var p1 = &x
    var p2 = &y
    #assert(#typeof(p1) == *s32)
    #assert(#typeof(p2) == *s32)
}

#test
{
    var x: s32
    var y = &(x)
    #assert(#typeof(y) == *s32)
}

#test
{
    var x: s32
    var y = &(x + x) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    var a: [4] s32
    var i = 1's32
    var p = &a[i]
    #assert(#typeof(p) == *s32)
}

#test
{
    var a: [4] s32
    var i = 1's32
    var p = &(a[i] + 1) // swc-expected-error {{sema_err_take_address_not_lvalue}}
}
