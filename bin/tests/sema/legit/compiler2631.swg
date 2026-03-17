#global fileprivate // swc-option sema-only
#global skip
func toto()
{
    #if true do
        struct AA {}
    var x: AA
}

#test
{
    toto()
}
