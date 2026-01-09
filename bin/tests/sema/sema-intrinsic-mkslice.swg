#global internal

#test
{
    //var buf: [100] u8
    //let str = cast(string) @mkslice(&buf[0], @strlen(&buf[0]))

    var buf: [100] u8
    let str = @mkslice(&buf[0], @strlen(&buf[0]))
    #assert(#typeof(str) == [..] u8)

    let str1 = @mkslice(&buf[0], 10)
    #assert(#typeof(str1) == [..] u8)
    let str2 = @mkslice(&buf[0], 10's16)
    #assert(#typeof(str2) == [..] u8)
}

#test
{
    var buf: [100] u8
    var str = @mkslice(0, @strlen(&buf[0])) // swc-expected-error {{sema_err_expected_type_fam}}
}

#test
{
    var buf: [100] u8
    var str = @mkslice(&buf[0], 0.0) // swc-expected-error {{sema_err_expected_type_fam}}
}
