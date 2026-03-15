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
