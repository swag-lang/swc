#global private

// Every dereference spelling needs a pointer operand: the prefix 'dref', the postfix
// place-deref 'expr[]', and the reinterpreting 'expr[as T]'.

#test
{
    var value: s32
    let bad = dref value     // swc-expected-error {{sema_err_deref_operand_type}}
}

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
