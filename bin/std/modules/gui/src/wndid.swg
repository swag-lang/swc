#global public

// Stable, non-null identifier used by windows, commands, and modal results.
//
// Use `#null WndId` when absence is meaningful.
alias WndId = string

// Declares a command identifier whose value is qualified by the current scope name.
#[Swag.Mixin]
func newCmdId(val: string)
{
    #ast "const " ++ val ++ " = \"" ++ #scopename ++ "." ++ val ++ "\""
}
