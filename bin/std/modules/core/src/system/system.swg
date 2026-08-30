#global public
#global namespace System

// Push a new execution context for the given block of code
#[Swag.Macro]
func pushContext(cxt: Swag.Context, stmt: #code)
{
    var prev = Swag.getContext()
    defer Swag.setContext(prev)

    Swag.setContext(cxt)
    #inject(stmt)
}
