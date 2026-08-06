#global public
#global namespace Debug

// Performs the assert operation.
#[Swag.Macro]
func assert(expr: #code->bool, message: #null string = null, loc = #callerlocation)
{
    #static if ASSERT
    {
        if !#inject(expr) do
            @panic(message, loc)
    }
}

// Performs the safety operation.
#[Swag.Macro]
func(what: Swag.SafetyWhat) safety(expr: #code->bool, message: #null string = null, loc = #callerlocation)
{
    #static if #safety(what)
    {
        if !#inject(expr) do
            @panic(message, loc)
    }
}

// Performs the safety bound check operation.
#[Swag.Macro]
func safetyBoundCheck(expr50: #code->bool, message: #null string = null, loc = #callerlocation)
{
    safety'(Swag.SafetyWhat.BoundCheck)(expr50, message, loc)
}
