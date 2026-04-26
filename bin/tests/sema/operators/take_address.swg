#global fileprivate

func functionAddressAsPointer()->s32 => 0

func functionAddressReturnedReference(value: &s32)->&s32
{
    return &value
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
    var a: [4] s32
    var p = &a[0]
    #assert(#typeof(p) == [*] s32)
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
    var A = 10's32
    var B = 20's32
    var PA = &A
    var PB = &B
    #assert(#typeof(PA) == *s32)
    #assert(#typeof(PB) == *s32)
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
    func refPtr(x: &s32)->*s32
    {
        let p = &x
        #assert(#typeof(p) == *s32)
        return p
    }

    func constRefPtr(x: const &s32)->*s32
    {
        let p = &x
        #assert(#typeof(p) == *s32)
        return p
    }

    var x: s32
    var y: s32
    var r: &s32 = &x
    r = #ref &y
    let p = &r
    #assert(#typeof(p) == *s32)
}

#test
{
    var a: [4] s32
    var i = 1's32
    var p = &a[i]
    #assert(#typeof(p) == [*] s32)
}

#test
{
    #assert(#typeof(&functionAddressAsPointer) == #type func()->s32)
    #assert(#typeof(cast(u64) functionAddressAsPointer()) == u64)
    let p = cast(const *void) &functionAddressAsPointer
    #assert(#typeof(p) == const *void)

    var value: s32
    let rp = &functionAddressReturnedReference(&value)
    #assert(#typeof(rp) == *s32)
}
