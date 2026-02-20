#global internal

#test
{
    var buf: [100] u8
    let str = @mkstring(&buf[0], 10)
    #assert(#typeof(str) == string)
    @assert(@countof(str) == 10)
}

#test
{
    var buf: [100] u8
    var str = @mkstring(0, 10) // swc-expected-error {{sema_err_expected_type_fam}}
}

#test
{
    var buf: [100] u8
    var str = @mkstring(&buf[0], 0.0) // swc-expected-error {{sema_err_cannot_cast}}
}
