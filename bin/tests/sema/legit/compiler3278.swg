#global fileprivate // swc-option sema-only
#global skip
func toto()
{
    #ast
    {
        #assert(#curlocation.funcName == "toto")
        return ""
    }
}
