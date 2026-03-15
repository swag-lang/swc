// swc-option suite-test

#global fileprivate
#global skip
func toto(x: ...)->u64 { return @countof(x) }

func toto1(x: u32...)->u64 { return @countof(x) }

#test
{
    @assert(toto() == 0)
    @assert(toto1() == 0)
}
