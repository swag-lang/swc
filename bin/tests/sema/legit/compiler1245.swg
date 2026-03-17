#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x: func()->void
    x = null
    if (x != null) do
        @assert(false)
    if (null != x) do
        @assert(false)
}
