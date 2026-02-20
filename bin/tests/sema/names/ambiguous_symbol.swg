#global internal

func Amb() {}
func Amb(a: s32) {}

#test
{
    Amb()
    Amb(10)
}

#test
{
    #assert(#nameof(Amb) == "Amb") // swc-expected-error {{sema_err_ambiguous_symbol}}
}

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

#test
{
    let p0 = #typeof(Amb) // swc-expected-error {{sema_err_ambiguous_symbol}}
}

#test
{
    let p1 = #typeof(N.Amb) // swc-expected-error {{sema_err_ambiguous_symbol}}
}
