#global public

alias WndId = string

#[Swag.Mixin]
func newCmdId(val: #nonull string)
{
    #ast "const " ++ val ++ " = \"" ++ #scopename ++ "." ++ val ++ "\""
}
