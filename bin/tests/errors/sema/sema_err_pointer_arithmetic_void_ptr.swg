#global fileprivate

#test
{
    var p: [*] void = null
    let a = p + 1 // swc-expected-error {{sema_err_pointer_arithmetic_void_ptr}}
}
