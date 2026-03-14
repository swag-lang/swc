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

#test
{
    var data: [5] s32 = [10, 20, 30, 40, 50]
    let base = &data[0]
    let p2 = base + 2
    let p4 = 4 + base
    let p1 = p4 - 3

    @assert(dref p2 == 30)
    @assert(dref p4 == 50)
    @assert(dref p1 == 20)
    @assert((p4 - base) == 4)
    @assert((p2 - p1) == 1)
}

#test
{
    var data: [4] u8 = [0, 1, 2, 3]
    var ptr         = &data[0]
    ptr += 1'u8
    @assert(ptr[0] == 1'u8)
    @assert(ptr[1] == 2'u8)
    ptr -= 1
    @assert(ptr[3] == 3'u8)
}

