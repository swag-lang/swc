#global fileprivate // swc-option sema-only
#global skip
//#global testerror
func(S = s32) toto()
{
    #assert(S == s32)
}

#test
{
    toto()
}
