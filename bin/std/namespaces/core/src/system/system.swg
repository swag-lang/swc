#global public
#global namespace System

// Runs `stmt` with `cxt` as the current execution context, then restores the previous one.
#[Swag.Macro]
func pushContext(cxt: Swag.Context, stmt: #code)
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    Swag.setContext(cxt)
    #inject(stmt)
}
