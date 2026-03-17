#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0244"

func titi() {}

func(T) toto(x: T) {}

#test
{
    toto(1)
}
