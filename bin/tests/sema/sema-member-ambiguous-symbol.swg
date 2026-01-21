#global internal

namespace N
{
    func Amb() {}
    func Amb(a: s32) {}
}

#test
{
    N.Amb()
    N.Amb(10)
}

#test
{
    #assert(#nameof(N.Amb) == "Amb") // swc-expected-error {{sema_err_ambiguous_symbol}}
}
