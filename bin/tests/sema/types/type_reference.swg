#global internal

struct A {}
func titi(a: &A) {}
#test
{
    var a: A
    titi(&a)
    titi(a) // swc-expected-error {{sema_err_cannot_cast}}
}

func tata(a: const &A) {}
#test
{
    var a: A
    tata(a)
}

#test
{
    var a: A
    var b: const &A // swc-expected-error {{sema_err_ref_missing_init}}
}

#test
{
    var a: A
    const b: const &A // swc-expected-error {{sema_err_const_ref_type}}
}

#test
{
    var a: A
    var b: &A = &a
    var c: const &A = &a
    var d: const &A = a
}
