#global fileprivate // swc-option suite-test

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
