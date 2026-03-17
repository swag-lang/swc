#global fileprivate // swc-option sema-only
#global skip
#test
{
    for #reverse 0
    {
        @assert(false)
    }
}
