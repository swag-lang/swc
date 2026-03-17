#global fileprivate // swc-option sema-only
#global skip
//#global testerror
struct ErrToto {}

func(T) toto()
{
    #if false do
        throw ErrToto{}
}

#test
{
    toto's32()
}
