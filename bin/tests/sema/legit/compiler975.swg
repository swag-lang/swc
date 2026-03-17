#global fileprivate // swc-option sema-only
#global skip
var pt = {1, 2}
#test
{
    @assert(pt.item0 == 1)
    @assert(pt.item1 == 2)
}
