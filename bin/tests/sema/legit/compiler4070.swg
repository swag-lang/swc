#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x = false
    var y = #ref &x
    while x
    {
        @assert(false)
    }
}
