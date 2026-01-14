#global internal

#test
{
    var buf: [100] u8
    let str = @mkslice(&buf[0], @strlen(@dataof(buf)))
    #assert(#typeof(str) == [..] u8)

    let str1 = @mkslice(&buf[0], 10)
    #assert(#typeof(str1) == [..] u8)
    let str2 = @mkslice(&buf[0], 10's16)
    #assert(#typeof(str2) == [..] u8)

    var ptr: const *s32
    let str3 = @mkslice(ptr, 20)
    #assert(#typeof(str3) == const [..] s32)
}

#test
{
    var buf2: [100] u8
    var str = @mkslice(0, @strlen(@dataof(buf2))) // swc-expected-error {{sema_err_expected_type_fam}}
}

#test
{
    var buf3: [100] u8
    var str = @mkslice(&buf3[0], 0.0) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var buf4: [100] u8
    let str4 = cast(string) @mkslice(&buf4[0], @strlen(@dataof(buf4)))
    #assert(#typeof(str4) == string)
}