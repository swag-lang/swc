#global fileprivate // swc-option sema-only
#global skip
func toto()
{
    #ast
    {
        return ""
    }

    //var a = 0
    #assert(true)
}
