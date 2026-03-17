#global fileprivate // swc-option sema-only
#global skip
#test
{
    #if false do
        #error("toto" ++ "titi")
}
