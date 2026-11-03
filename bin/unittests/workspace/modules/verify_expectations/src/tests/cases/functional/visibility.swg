#global if #command == Swag.CompilerCommand.Test
#global private

using ExportApi

// A public file and its unqualified impl publish their declarations once, while an aggregate
// still publishes fields deliberately and can make a public field read-only.
#test
{
    var value = DepVisibility.create(2, 3, 5, 7)
    Swag.assert(value.writable == 2)
    Swag.assert(value.observed == 3)
    Swag.assert(value.total() == 2 + 3 + 5 + 6 + 7)

    value.writable = 11
    Swag.assert(value.total() == 11 + 3 + 5 + 6 + 7)
}

#test
{
    var value = DepVisibility.create(2, 3, 5, 7)
    value.observed = 9     // swc-expected-error {{sema_err_field_readonly}}
}

#test
{
    let value = DepVisibility.create(2, 3, 5, 7)
    Swag.assert(value.moduleState == 5)     // swc-expected-error {{sema_err_field_internal}}
}

#test
{
    let value = DepVisibility.create(2, 3, 5, 7)
    Swag.assert(value.moduleObserved == 6)     // swc-expected-error {{sema_err_field_internal}}
}
