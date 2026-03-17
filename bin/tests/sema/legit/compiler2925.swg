#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x: any = "t"
    switch x
    {
    case s32:
        @assert(false)
    case string:
        break
    default:
        @assert(false)
    }
}
