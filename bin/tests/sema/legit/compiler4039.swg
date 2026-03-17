#global fileprivate // swc-option sema-only
#global skip
//#global testerror
func(S = s32, T = bool) toto()
{
    #assert(S == s32)
    #assert(T == bool)
}

#test
{
    toto()
}
