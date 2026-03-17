#global fileprivate // swc-option sema-only
#global skip
#global skip
func C(value: const& s64)
{
    @assert(value == 2)
}

#test
{
    C(2's64)
}
