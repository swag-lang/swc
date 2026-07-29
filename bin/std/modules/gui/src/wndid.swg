#global public

// Names the wnd id type.
alias WndId = #null string

// Performs the new cmd id operation.
#[Swag.Mixin]
func newCmdId(val: string)
{
    #ast "const " ++ val ++ " = \"" ++ #scopename ++ "." ++ val ++ "\""
}
