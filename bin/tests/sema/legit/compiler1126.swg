#global fileprivate // swc-option sema-only
#global skip
func titi(line: u32 = #line)
{
    @assert(line == 8)
}

#test
{
    titi(#line)
}
