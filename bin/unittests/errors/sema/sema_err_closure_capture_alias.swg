#global private

struct AliasCapture24
{
    a, b, c: u64
}

struct AliasCaptureWithDrop
{
    value: s32
}

impl AliasCaptureWithDrop
{
    mtd opDrop() {}
}

alias AliasCaptureNullary = func||()->s32

#test
{
    let left  = 1
    let right = 2
    let bad: AliasCaptureNullary = func|value = left, value = right|()->s32 { return value } // swc-expected-error {{sema_err_closure_capture_duplicate}}
}

#test
{
    let outer = 10
    let bad: AliasCaptureNullary = func|sum = outer + 1|()->s32 { return outer + sum } // swc-expected-error {{sema_err_closure_capture_missing}}
}

#test
{
    var value = AliasCaptureWithDrop{1}
    let bad: AliasCaptureNullary = func|copy = value|()->s32 { return copy.value } // swc-expected-error {{sema_err_closure_capture_lifecycle}}
}

#test
{
    let fixed = 10
    let bad: AliasCaptureNullary = func|&current = fixed|()->s32 { return current } // swc-expected-error {{sema_err_closure_capture_let_by_ref}}
}

#test
{
    var left  = 1
    var right = 2
    let bad: AliasCaptureNullary = func|&sum = left + right|()->s32 { return sum } // swc-expected-error {{sema_err_take_address_not_lvalue}}
}

#test
{
    let a = AliasCapture24{a: 1, b: 2, c: 3}
    let b = AliasCapture24{a: 4, b: 5, c: 6}
    let c = AliasCapture24{a: 7, b: 8, c: 9}
    let bad = func|first = a, second = b, third = c|() {} // swc-expected-error {{sema_err_closure_capture_too_large}}
}
