// 

#global fileprivate
#global skip
func append()->bool
    where
    {
        @assert(#curlocation.funcName == "append")
        return true
    }
{
    return true
}

#test
{
    @assert(append())
}
