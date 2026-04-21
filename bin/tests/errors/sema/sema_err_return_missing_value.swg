#global fileprivate

func test3() -> s32
{
    return; // swc-expected-error {{sema_err_return_missing_value}}
}
