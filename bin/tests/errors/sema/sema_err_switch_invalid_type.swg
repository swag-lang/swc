#global fileprivate

#test
{
    var a : [4] s32
    switch a // swc-expected-error {{sema_err_switch_invalid_type}}
    {
        default:
            break
    }
}
