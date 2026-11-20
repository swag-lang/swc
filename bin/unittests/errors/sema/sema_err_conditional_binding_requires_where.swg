#global private

func implicitInteger(value: s32)
{
    if let count = value     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
    {
        discard count
    }
}

func implicitBool(value: bool)
{
    if var enabled = value     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
    {
        discard enabled
    }
}

func implicitConstant()
{
    if const count = 0     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
    {
        discard count
    }
}

func implicitElseIf(first: bool, value: s32)
{
    if first do
        return
    elif let count = value     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
    {
        discard count
    }
}

func implicitIntegerCase(value: s32)
{
    switch
    {
    case let count = value:     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
        discard count
    }
}

func implicitBoolCase(value: bool)
{
    switch
    {
    case var enabled = value:     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
        discard enabled
    }
}

func implicitConstantCase()
{
    switch
    {
    case const count = 0:     // swc-expected-error {{sema_err_conditional_binding_requires_where}}
        discard count
    }
}
