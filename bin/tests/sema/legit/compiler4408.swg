#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0576"
func(T) toto(x: T) {}

#test
{
    toto({2's32})
}
