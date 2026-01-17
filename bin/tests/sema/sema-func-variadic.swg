#global internal

func titi(a: ...) {}
func tata(a: s32...) {}

#test
{
    titi("a", "b")
    tata(1, 2, 3)
    tata("a") // swc-expected-error {{sema_err_cannot_cast}}
}

func toto(a: s32, b: ...) {}
#test
{
    toto(1, "a", "b")
    toto(1)
}

func tutu(a: s32, b: s32...) {}
#test
{
    tutu(1)
    tutu(1, 2)
    tutu(1, 2, 3)
}