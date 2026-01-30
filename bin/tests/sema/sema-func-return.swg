func test1()
{
    return;
}

func test2() -> s32
{
    return 10;
}

func test3() -> s32
{
    return; // swc-expected-error {{sema_err_return_missing_value}}
}

func test4()
{
    return 10; // swc-expected-error {{sema_err_return_value_in_void}}
}

func test5() -> s32
{
    return "string"; // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    return; // swc-expected-error {{sema_err_return_outside_func}}
}
