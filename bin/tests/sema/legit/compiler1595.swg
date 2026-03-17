#global fileprivate // swc-option sema-only
#global skip
#test
{
    var g = 0
    #ast "g = 666"
    @assert(g == 666)
}
