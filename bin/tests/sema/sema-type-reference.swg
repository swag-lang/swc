#global internal

struct A {}
func titi(a: &A) {}
#test
{
    var a: A
    titi(&a)
    /*titi(a) // swc-expected-error {{sema_err_cannot_cast}}*/
}

func tata(a: const &A) {}
#test
{
    var a: A
    tata(a)
}