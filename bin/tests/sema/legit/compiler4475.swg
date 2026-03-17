#global fileprivate // swc-option sema-only
#global skip
#test
{
    var g = false
    if let x = 1
    {
        g = true
    }

    @assert(g)
}
