#global fileprivate

#test
{
    var buf: [100] u8
    var str = @mkstring(0, 10) // swc-expected-error {{sema_err_expected_type_fam}}
}
