#global if #command == Swag.CompilerCommand.Test
#global private

using ExportApi

// A member of an imported type is reached only when it says 'public'. The default is 'internal',
// which grants the module that declares the type and nobody else, so an importing module sees
// exactly the state the provider published.
#test
{
    let value = makeDepDefaultAccessField(7)
    @assert(value.shownValue == 7)
    @assert(value.defaultValue == 8)     // swc-expected-error {{sema_err_field_internal}}
}

#test
{
    var value = makeDepDefaultAccessField(7)
    value.defaultValue = 1     // swc-expected-error {{sema_err_field_internal}}
}

// Naming a field in a literal writes it, so the rule reaches a literal too.
#test
{
    discard DepDefaultAccessField{shownValue: 1, defaultValue: 2}     // swc-expected-error {{sema_err_struct_cast_field_access}}
}
