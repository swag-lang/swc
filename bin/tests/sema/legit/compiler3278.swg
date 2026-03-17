#global fileprivate
#global skip
func toto()
{
    #ast
    {
        #assert(#curlocation.funcName == "toto")
        return ""
    }
}
