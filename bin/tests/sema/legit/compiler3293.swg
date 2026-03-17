#global fileprivate // swc-option sema-only
#global skip
#test
{
    var a = 0
    if a == 1 do
        @assert(false)
    elif a == 0 do
        a = 2
    @assert(a == 2)
}
