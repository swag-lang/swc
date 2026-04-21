#global fileprivate

#test
{
    var A = 10's32
    var PB = &0 // swc-expected-error {{sema_err_take_address_constant}}
}
