#global private

#test
{
    if let x = 1 where x == 1
    {
        let y = x
    }
    else
    {
        let z = x
    }

    let w = x     // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    if let x = 4 where x > 2
    {
        let y = x; discard y
    }
}

#test
{
    if let x = 1 where false {}
    else
    {
        let y = x; discard y
    }
}

#test
{
    if let x = 4 where x > 2
    {
        let y = x
        discard y
    }
}

struct Broken
{
    field: MissingType     // swc-expected-error {{sema_err_unknown_symbol}}
}

const BrokenSize = #sizeof(Broken)

func caseBindingNotVisibleInSibling(value: *s32?, flag: bool)
{
    switch
    {
    case let binding = value:
        discard binding
    case flag:
        discard binding     // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

func caseBindingNotVisibleInDefault(value: *s32?)
{
    switch
    {
    case let binding = value:
        discard binding
    default:
        discard binding     // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

func caseBindingNotVisibleAfterSwitch(value: *s32?)
{
    switch
    {
    case let binding = value:
        discard binding
    }
    discard binding     // swc-expected-error {{sema_err_unknown_symbol}}
}
