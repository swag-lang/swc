#global fileprivate // swc-option sema-only
#global skip
#test
{
    var a: string
    if a do
        @assert(false)
    a = ""
    if !a do
        @assert(false)
}
