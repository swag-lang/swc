#global fileprivate
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
