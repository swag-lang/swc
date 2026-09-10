#global internal

namespace InlineCodePayloadDebug
{
    // The shape of 'Debug.safetyBoundCheck': a generic macro whose '#code' argument is written in
    // an inline body of ANOTHER file and names that body's parameter and its elided receiver
    // member. Three files, as with 'core': the macro, the container, and the caller.
    #[Swag.Macro]
    func(what: Swag.SafetyWhat) guard(expr: #code->bool, message: string? = null, loc = #callerlocation)
    {
        #static if #safety(what)
        {
            if not #inject(expr) do
                Swag.panic(message, loc)
        }
    }

    #[Swag.Macro]
    func bound(expr50: #code->bool, message: string? = null, loc = #callerlocation)
    {
        guard'(Swag.SafetyWhat.BoundCheck)(expr50, message, loc)
    }
}
