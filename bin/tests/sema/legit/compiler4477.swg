#global fileprivate // swc-option sema-only
#global skip
#test
{
    var g = false
    if var x: string
    {
        g = true
    }

    @assert(g == false)
}
