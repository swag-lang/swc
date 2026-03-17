#global fileprivate // swc-option sema-only
#global skip
func toto(t: typeinfo) {}

func(T) titi(x: T)
{
    toto(T)
}

//#[Swag.PrintBc]
#test
{
    let x = func() {}

    titi(x)
}
