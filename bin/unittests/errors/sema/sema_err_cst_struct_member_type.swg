#global private

struct PtrHolder
{
    value: *u8
}

func makePtrHolder()->PtrHolder
{
    var local: u8 = 1
    return {value: &local} // swc-expected-warning {{sema_warn_borrow_escape}}
}

struct FnHolder
{
    value: func()->s32
}

func constFn()->s32 => 1
func makeFnHolder()->FnHolder => {value: &constFn}

const ptrHolder = #run makePtrHolder()
const ptrValue = ptrHolder.value // swc-expected-error {{sema_err_cst_struct_member_type}}

// A function-typed field is no longer a hard "cannot be evaluated" error during extraction; it
// simply does not const-fold (its address is a link-time value) and is read at runtime. In this
// const-required context that surfaces as the generic compile-time-constant requirement instead.
const fnHolder = #run makeFnHolder()
const fnValue = fnHolder.value // swc-expected-error {{sema_err_expr_not_const}}
