#global internal

func titi(a: ...) {}
func tata(a: s32...) {}

#test
{
    titi("a", "b")
    tata(1, 2, 3)
    tata("a") // swc-expected-error {{sema_err_cannot_cast}}
}