#global fileprivate // swc-option sema-only
#global skip
func toto()->typeinfo
{
    return s32
}

#test
{
    @assert(toto() == s32)
}
