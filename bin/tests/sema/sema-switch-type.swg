#global internal

#test
{
    var a: typeinfo = s32
    switch a
    {
        case s32: break
    }
}

#test
{
    var a: typeinfo = s32
    switch a
    {
        case s32: break
        case s32: break // swc-expected-error {{sema_err_switch_case_duplicate}}
    }
}

#test
{
    var a: typeinfo = f32
    switch a
    {
        case s32: break
        default: break
    }
}
