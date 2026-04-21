#global fileprivate

#test
{
    var x = 0
    var x = 0 // swc-expected-error {{sema_err_already_defined}}
}
