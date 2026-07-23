#global private

struct Movable
{
    value: s32
}

#[Swag.Macro]
func macroValueParameter(value: Movable)
{
}

#test
{
    var value = Movable{1}
    macroValueParameter(#move value) // swc-expected-error {{sema_err_move_arg_macro_value}}
}
