#global fileprivate // swc-option sema-only
#global skip
struct ErrToto {}

#test
{
    toto()
}

func toto()
{
    titi()
    #if false do
        throw ErrToto{}
}

func titi()
{
    #if false do
        throw ErrToto{}
}
