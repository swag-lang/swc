#global fileprivate // swc-option suite-test

#test
{
    var a: typeinfo = s32
    var hit = 0
    switch a
    {
        case s32:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var a: typeinfo = s32
    var hit = 0
    switch a
    {
        case s32:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var a: typeinfo = f32
    var hit = 0
    switch a
    {
        case s32:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 2)
}
