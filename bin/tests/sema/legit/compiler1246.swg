#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x: func()->void
    if x or x do
        @assert(false)
}
