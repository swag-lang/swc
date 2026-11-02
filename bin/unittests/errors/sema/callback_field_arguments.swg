#global private

struct CallbackField
{
    callback: func(*u8)
    owned:    func(*CallbackField)
}

func nullableArgument(field: *CallbackField, value: *u8?)
{
    field.callback(value)     // swc-expected-error {{sema_err_cannot_cast}}
}

func deferredArgument(field: *CallbackField, value: *u8?)
{
    Swag.assert(value != null)
    defer field.callback(value)     // swc-expected-error {{sema_err_cannot_cast}}
}

func missingOwnerArgument(field: *CallbackField)
{
    field.owned()     // swc-expected-error {{sema_err_too_few_arguments}}
}
