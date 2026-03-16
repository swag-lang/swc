#global fileprivate // swc-option suite-test

#test
{
    var buf: [100] u8
    let str = @mkslice(&buf[0], @countof(buf))
    #assert(#typeof(str) == [..] u8)

    let str1 = @mkslice(&buf[0], 10)
    #assert(#typeof(str1) == [..] u8)
    let str2 = @mkslice(&buf[0], 10's16)
    #assert(#typeof(str2) == [..] u8)

    var ptr: const *s32
    let str3 = @mkslice(ptr, 20)
    #assert(#typeof(str3) == const [..] s32)
    @assert(@countof(str) == 100)
    @assert(@countof(str1) == 10)
    @assert(@countof(str2) == 10)
    @assert(@countof(str3) == 20)
}



#test
{
    var buf4: [100] u8
    let str4 = cast(string) @mkslice(&buf4[0], @countof(buf4))
    #assert(#typeof(str4) == string)
    @assert(@countof(str4) == 100)
}

#test
{
    var buf: [4] u8 = [10, 20, 30, 40]
    let sl = @mkslice(&buf[2], 0)

    #assert(#typeof(sl) == [..] u8)
    @assert(@countof(sl) == 0)
}

#test
{
    var buf: [5] u8 = [1, 2, 3, 4, 5]
    let sl = @mkslice(&buf[1], 3)

    @assert(@countof(sl) == 3)
    @assert(sl[0] == 2)
    @assert(sl[1] == 3)
    @assert(sl[2] == 4)
}

#test
{
    var buf: [4] u16 = [11, 22, 33, 44]
    let sl = @mkslice(&buf[0], 4)

    sl[1] = 77
    sl[3] = 99

    #assert(#typeof(sl) == [..] u16)
    @assert(buf[1] == 77)
    @assert(buf[3] == 99)
}

#test
{
    var buf: [3] s32 = [5, 6, 7]
    let ptr: const *s32 = &buf[0]
    let sl = @mkslice(ptr, 3)

    #assert(#typeof(sl) == const [..] s32)
    @assert(@countof(sl) == 3)
    @assert(sl[0] == 5)
    @assert(sl[2] == 7)
}
