#global fileprivate // swc-option suite-test

#test
{
    var p: [*]s32 = null

    var off1: u8 = 1

    let a = p + 1
    #assert(#typeof(a) == [*]s32)

    let a2 = p + off1
    #assert(#typeof(a2) == [*]s32)

    let b = 1 + p
    #assert(#typeof(b) == [*]s32)

    let b2 = off1 + p
    #assert(#typeof(b2) == [*]s32)

    let c = p - 1
    #assert(#typeof(c) == [*]s32)

    let c2 = p - off1
    #assert(#typeof(c2) == [*]s32)
}

#assert(#typeof((cast([*]s32) null) - (cast([*]s32) null)) == s64)



