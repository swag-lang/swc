#global fileprivate

func test4()
{
    return 10; // swc-expected-error {{sema_err_return_value_in_void}}
}
