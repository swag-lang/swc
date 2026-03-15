// swc-option suite-test

#global fileprivate
#global skip
func toto()->bool { return true }

#test
{
    @assert(toto())
}
