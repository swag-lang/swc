#global fileprivate // swc-option sema-only
#global skip
func toto()
{
    #assert(#curlocation.funcName == "toto")

    var fct = func()
    {
        #assert(#curlocation.funcName != "")
    }
}
