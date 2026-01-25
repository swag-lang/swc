#global internal

func toto()->{x: s32, y: bool}
{
    return {42, true}
}

#test
{
    let s = toto()
    #assert(#typeof(s).kind == .Struct)
    let (a, b) = s
    #assert(#typeof(a) == s32)
    #assert(#typeof(b) == bool)
}

#test
{
    let (a, b) = 12 // swc-expected-error {{sema_err_decomposition_not_struct}}
}

#test
{
    let (a, b, c) = toto() // swc-expected-error {{sema_err_decomposition_too_many_names}}
}

#test
{
    let (a) = toto() // swc-expected-error {{sema_err_decomposition_not_enough_names}}
}

#test
{
    let s = toto()
    let (a, b) = s
    let (a, b) = s // swc-expected-error {{sema_err_already_defined}}
}