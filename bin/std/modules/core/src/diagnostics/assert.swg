#global public
#global namespace Debug

// Panics with `message` when `expr` is false, if the safety check `what` is enabled for the calling code.
//
// When the check is disabled, `expr` is not evaluated.
#[Swag.Macro]
func(what: Swag.SafetyWhat) safety(expr: #code->bool, message: string? = null, loc = #callerlocation)
{
    #static if #safety(what)
    {
        if not #inject(expr) do
            Swag.panic(message, loc)
    }
}

// Checks `expr50` like [[Core.Debug.safety]] under the bound-check safety category.
#[Swag.Macro]
func safetyBoundCheck(expr50: #code->bool, message: string? = null, loc = #callerlocation)
{
    safety'(Swag.SafetyWhat.BoundCheck)(expr50, message, loc)
}
