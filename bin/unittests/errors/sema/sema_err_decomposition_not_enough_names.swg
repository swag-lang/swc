#global fileprivate

func toto()->{x: s32, y: bool}
{
    return {42, true}
}

#test
{
    let (a) = toto() // swc-expected-error {{sema_err_decomposition_not_enough_names}}
}
