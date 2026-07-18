#global public
#global namespace System
#global #[Swag.ExplicitNullability]

// Push a new execution context for the given block of code
#[Swag.Macro]
func pushContext(cxt: Swag.Context, stmt: #code)
{
    var prev = @getcontext()
    defer @setcontext(prev)

    @setcontext(cxt)
    #inject(stmt)
}
