#global private

// Every dereference needs a pointer operand: the place-deref 'expr[]' and the
// reinterpreting 'expr[as T]'.

#test
{
    var value: s32
    let bad = value[]     // swc-expected-error {{sema_err_deref_operand_type}}
}

#test
{
    var a = [1, 2, 3]
    var b = a[]     // swc-expected-error {{sema_err_deref_operand_type}}
}

#test
{
    var c = "abc"[]     // swc-expected-error {{sema_err_deref_operand_type}}
}

#test
{
    var value: s32
    let bad = value[as u32]     // swc-expected-error {{sema_err_deref_operand_type}}
}
