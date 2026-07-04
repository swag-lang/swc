#global private

struct MoveCtxVec { x: s32 }

// A move reference is allowed as a function parameter type.
func takeMoveCtx(v: #move MoveCtxVec) {}

#test
{
    var v: MoveCtxVec
    takeMoveCtx(#move v)
}

#test
{
    var v = MoveCtxVec{1}
    var rr: #move MoveCtxVec = (#move v) // swc-expected-error {{sema_err_move_ref_type_context}}
}

#test
{
    struct BadField
    {
        r: #move MoveCtxVec // swc-expected-error {{sema_err_move_ref_type_context}}
    }
}

#test
{
    func badReturn(v: #move MoveCtxVec)->#move MoveCtxVec // swc-expected-error {{sema_err_move_ref_type_context}}
    {
        return v
    }
}

#test
{
    var cb: func(v: #move MoveCtxVec)->#move MoveCtxVec // swc-expected-error {{sema_err_move_ref_type_context}}
}
