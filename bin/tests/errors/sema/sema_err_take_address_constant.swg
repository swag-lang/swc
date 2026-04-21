#global fileprivate

// Taking the address of a constant expression is not allowed; only lvalues are addressable.
#test
{
    var a = &0                   // swc-expected-error {{sema_err_take_address_constant}}
}

#test
{
    var b = &42'u32              // swc-expected-error {{sema_err_take_address_constant}}
}

#test
{
    var c = &"hi"                // swc-expected-error {{sema_err_take_address_constant}}
}
