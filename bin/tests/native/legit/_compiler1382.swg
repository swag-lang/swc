// 

#global fileprivate
func toto()->bool { return true }

#test
{
    @assert(toto())
}

