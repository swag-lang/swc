#global public

alias WndId = #null string

#[Swag.Mixin]
func newCmdId(val: string)
{
    #ast "const " ++ val ++ " = \"" ++ #scopename ++ "." ++ val ++ "\""
}
