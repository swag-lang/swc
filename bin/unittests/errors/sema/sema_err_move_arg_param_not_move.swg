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

func plainStore(v: Vec) {}
func plainScalar(v: s32) {}

// An explicit '#move' argument requires a '#move' parameter: it is not silently
// degraded to a copy.
#test
{
    var t = Vec{1}
    plainStore(#move t) // swc-expected-error {{sema_err_move_arg_param_not_move}}
}

#test
{
    var n = 3
    plainScalar(#move n) // swc-expected-error {{sema_err_move_arg_param_not_move}}
}
