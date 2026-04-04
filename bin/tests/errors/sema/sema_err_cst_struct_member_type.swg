#global fileprivate

struct PtrHolder
{
    value: *u8
}

func makePtrHolder()->PtrHolder
{
    var local: u8 = 1
    return {value: &local}
}

struct FnHolder
{
    value: func()->s32
}

func constFn()->s32 => 1
func makeFnHolder()->FnHolder => {value: &constFn}

const ptrHolder = #run makePtrHolder()
const ptrValue = ptrHolder.value // swc-expected-error {{sema_err_cst_struct_member_type}}

const fnHolder = #run makeFnHolder()
const fnValue = fnHolder.value // swc-expected-error {{sema_err_cst_struct_member_type}}
