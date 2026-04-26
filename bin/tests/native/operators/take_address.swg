#global fileprivate // 

func nativeFunctionAddressAsPointer()->s32 => 1

func nativeFunctionAddressReturnedReference(value: &s32)->&s32
{
    return &value
}

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    var v: *AA = &st
    #assert(#typeof(v) == *AA)
    @assert(v == &st)
}

#test
{
    var A = 10's32
    var PA = &A
    #assert(#typeof(PA) == *s32)
    @assert(dref PA == 10)
}

#test
{
    var x: [4] s32
    var px = &x
    #assert(#typeof(px) == [*][4] s32)
    @assert(px == &x)
}

#test
{
    struct AA { x: s32 }
    var x = 0
    @assert(x == 0)
}

#test
{
    struct AA { x: s32 }
    var st: AA
    var z = &st.x
    @assert(z == &st.x)
}

#test
{
    var x: s32
    var px = &x
    #assert(#typeof(px) == *s32)
    @assert(px == &x)
}

#test
{
    var x: s32
    var px = &x
    var ppx = &px
    #assert(#typeof(ppx) == **s32)
    @assert(dref ppx == &x)
}


#test
{
    var a: [4] s32
    var p = &a[0]
    #assert(#typeof(p) == [*] s32)
    @assert(p == &a[0])
}


#test
{
    struct B { y: s32 }
    struct C { b: B }
    var c: C
    var p = &c.b.y
    #assert(#typeof(p) == *s32)
    @assert(p == &c.b.y)
}

#test
{
    struct AA { x: s32 }
    var st: AA
    var p1 = &st
    #assert(#typeof(p1) == *AA)
    @assert(p1 == &st)
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
    @assert(px == &y)
    @assert(py == &y)
}

#test
{
    var A = 10's32
    var B = 20's32
    var PA = &A
    var PB = &B
    #assert(#typeof(PA) == *s32)
    #assert(#typeof(PB) == *s32)
    @assert(dref PA + dref PB == 30)
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
    @assert(dref ppx == &x)
    @assert(dref ppy == &y)
}

#test
{
    var x: s32
    var y = x
    var p1 = &x
    var p2 = &y
    #assert(#typeof(p1) == *s32)
    #assert(#typeof(p2) == *s32)
    @assert(p1 != p2)
}

#test
{
    var x: s32
    var y = &(x)
    #assert(#typeof(y) == *s32)
    @assert(y == &x)
}

#test
{
    func mutateThroughRefPtr(x: &s32)
    {
        let p = &x
        #assert(#typeof(p) == *s32)
        dref p = 55
    }

    func inspectConstRefPtr(x: const &s32, expected: s32)
    {
        let p = &x
        #assert(#typeof(p) == *s32)
        @assert(dref p == expected)
    }

    var x: s32 = 10
    mutateThroughRefPtr(&x)
    @assert(x == 55)

    inspectConstRefPtr(x, 55)
    inspectConstRefPtr(4, 4)
    inspectConstRefPtr(2 + 5, 7)

    var y: s32 = 91
    var r: &s32 = &x
    r = #ref &y
    let rebound = &r
    #assert(#typeof(rebound) == *s32)
    dref rebound = 123
    @assert(x == 55)
    @assert(y == 123)
}


#test
{
    var a: [4] s32
    var i = 1's32
    var p = &a[i]
    #assert(#typeof(p) == [*] s32)
    @assert(p == &a[1])
}

// Taking the address of a constant array element.
#test
{
    const a: [3] s32 = [10, 20, 30]
    let p = &a[0]
    #assert(#typeof(p) == const [*] s32)
    @assert(p[0] == 10)
    @assert(p[2] == 30)
}

#test
{
    const a: [4] u8 = [1, 2, 3, 4]
    let p = &a[2]
    #assert(#typeof(p) == const [*] u8)
    @assert(p[0] == 3)
}

#test
{
    #assert(#typeof(&nativeFunctionAddressAsPointer) == #type func()->s32)
    #assert(#typeof(cast(u64) nativeFunctionAddressAsPointer()) == u64)
    let p = cast(const *void) &nativeFunctionAddressAsPointer
    #assert(#typeof(p) == const *void)
    @assert(p != null)

    var value = 77
    let rp = &nativeFunctionAddressReturnedReference(&value)
    #assert(#typeof(rp) == *s32)
    @assert(rp == &value)
}
