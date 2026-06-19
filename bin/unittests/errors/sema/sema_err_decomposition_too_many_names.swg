#global fileprivate

func toto()->{x: s32, y: bool}
{
    return {42, true}
}

#test
{
    let (a, b, c) = toto() // swc-expected-error {{sema_err_decomposition_too_many_names}}
}
