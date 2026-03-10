// swc-option suite-test

#global fileprivate
#global skip
func append()
    where
    {
        @assert(#curlocation.funcName == "append")
        return true
    }
{
}

#test
{
    append()
}
