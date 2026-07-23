#global private

struct PlainField
{
    value: s32
}

func testPlainField(value: *PlainField)->bool
{
    return #isset(value.value)     // swc-expected-error {{sema_err_isset_not_late_field}}
}

func testLocal(value: s32)->bool
{
    return #isset(value)     // swc-expected-error {{sema_err_isset_not_late_field}}
}
