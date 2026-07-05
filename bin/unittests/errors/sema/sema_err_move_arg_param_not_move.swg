#global private

struct Vec
{
    x: s32
}

impl Vec
{
    mtd opPostCopy() {}
    mtd opPostMove() {}
    mtd opDrop() {}
}

func refStore(v: &Vec) {}
func ptrStore(v: *Vec) {}

// An explicit '#move' argument requires a parameter that can receive the transfer: a
// reference or pointer parameter would silently ignore it.
#test
{
    var t = Vec{1}
    refStore(#move t) // swc-expected-error {{sema_err_move_arg_param_not_move}}
}

#test
{
    var t = Vec{2}
    ptrStore(#move t) // swc-expected-error {{sema_err_move_arg_param_not_move}}
}
