#global public

// Stable, non-null identifier used by windows, commands, and modal results.
//
// Use `WndId?` when absence is meaningful.
alias WndId = string

// Declares a constant named `val` whose value is `val` qualified by the current scope name.
#[Swag.Mixin]
func newCmdId(val: string)
{
    #ast("const ", val, " = \"", #scopename, ".", val, "\"")
}
