#global private

struct Movable
{
    value: s32
}

#[Swag.Macro]
func macroMoveParameter(value: #move Movable) {}

#test
{
    var value = Movable{1}
    macroMoveParameter(value) // swc-expected-error {{sema_err_move_arg_macro}}
}
