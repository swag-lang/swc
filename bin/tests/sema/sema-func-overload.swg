#global internal

func A() {}
func A(a: s32) {}

#test
{
    A()
    A(10)
    A(10, 10) // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    A("a") // swc-expected-error {{sema_err_no_overload_match}}
}
