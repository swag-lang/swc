#global public
#global namespace Debug

// Performs the safety operation.
#[Swag.Macro]
func(what: Swag.SafetyWhat) safety(expr: #code->bool, message: string? = null, loc = #callerlocation)
{
    #static if #safety(what)
    {
        if not #inject(expr) do
            Swag.panic(message, loc)
    }
}

// Performs the safety bound check operation.
#[Swag.Macro]
func safetyBoundCheck(expr50: #code->bool, message: string? = null, loc = #callerlocation)
{
    safety'(Swag.SafetyWhat.BoundCheck)(expr50, message, loc)
}
