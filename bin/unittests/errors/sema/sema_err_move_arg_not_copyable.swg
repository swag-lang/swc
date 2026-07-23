#global private

// A plain value can bind a '#move' parameter only if its type is copyable (the call
// site materializes a temporary copy). A struct marked with '#[Swag.NoCopy]' is
// non-copyable: the call must pass the value with '#move'.
#[Swag.NoCopy]
struct MoveOnly { x: s32 }
impl MoveOnly
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

var g_target: MoveOnly

func sink(v: #move MoveOnly)
{
    g_target = #nodrop #move v
}

#test
{
    var m = MoveOnly{1}
    sink(m)     // swc-expected-error {{sema_err_move_arg_not_copyable}}
}
