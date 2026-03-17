#global fileprivate // swc-option sema-only
#global skip
#test
{
    const z = "null"
    @assert(null != z)
}
