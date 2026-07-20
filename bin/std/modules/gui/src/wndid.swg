#global public

alias WndId = #null string

#[Swag.Mixin]
func newCmdId(val: #nonull string)
{
    #ast "const " ++ val ++ " = \"" ++ #scopename ++ "." ++ val ++ "\""
}
