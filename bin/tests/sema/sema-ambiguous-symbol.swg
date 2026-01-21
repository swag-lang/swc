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
