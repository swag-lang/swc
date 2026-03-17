#global fileprivate // swc-option sema-only
#global skip
func toto()
{
    #if true
    {
        func titi()
        {
            #if true do
                struct AA {}
            var x: AA
        }
    }

    titi()
}

#test
{
    toto()
}
