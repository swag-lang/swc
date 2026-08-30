#global private

struct PlainField
{
    value: s32
}

func testPlainField(value: *PlainField)->bool
{
    return Swag.isSet(value.value)     // swc-expected-error {{sema_err_isset_not_late_field}}
}

func testLocal(value: s32)->bool
{
    return Swag.isSet(value)     // swc-expected-error {{sema_err_isset_not_late_field}}
}

// A plain (non-'Swag.Late') global is not a valid 'Swag.isSet' operand either.
var g_plainGlobal: s32

func testPlainGlobal()->bool
{
    return Swag.isSet(g_plainGlobal)     // swc-expected-error {{sema_err_isset_not_late_field}}
}
