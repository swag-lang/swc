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
    var rr: #move MoveCtxVec = (#move v)     // swc-expected-error {{sema_err_move_ref_type_context}}
}

#test
{
    struct BadField
    {
        r: #move MoveCtxVec     // swc-expected-error {{sema_err_move_ref_type_context}}
    }
}

#test
{
    func badReturn(v: #move MoveCtxVec)->#move MoveCtxVec     // swc-expected-error {{sema_err_move_ref_type_context}}
    {
        return v
    }
}

#test
{
    var cb: func(v: #move MoveCtxVec)->#move MoveCtxVec     // swc-expected-error {{sema_err_move_ref_type_context}}
}

// A conditional joins two values, so neither branch can transfer ownership. Both spellings are
// reported, and neither reaches code generation.
#test
{
    var v    = MoveCtxVec{1}
    var w    = MoveCtxVec{2}
    let cond = v.x == 99
    var picked = cond ? w : #move v     // swc-expected-error {{sema_err_move_ref_type_context}}
    discard picked
}

#test
{
    var v    = MoveCtxVec{1}
    var w    = MoveCtxVec{2}
    let cond = v.x == 99
    var picked = cond ? #move v : w     // swc-expected-error {{sema_err_move_ref_type_context}}
    discard picked
}

// An owning value: '#move' on it is a real transfer, not a copy the compiler can undo.
struct MoveCtxOwner
{
    x: s32
}

impl MoveCtxOwner
{
    mtd opDrop() {}
    mtd opPostMove() {}
}

struct MoveCtxPair
{
    kind:  s32
    value: MoveCtxOwner
}

func takeMoveCtxPair(p: MoveCtxPair) { discard p }

// A literal is materialized as a value, so an element cannot hand over storage either.
#test
{
    var v = MoveCtxOwner{1}
    takeMoveCtxPair(MoveCtxPair{3, #move v})     // swc-expected-error {{sema_err_move_ref_type_context}}
}

#test
{
    var v = MoveCtxOwner{1}
    var a = [MoveCtxOwner{2}, #move v]     // swc-expected-error {{sema_err_move_ref_type_context}}
    discard a
}
