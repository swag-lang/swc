#global private

// A constraint admits Add, so a misspelled enum member in the selected body is reported
// instead of silently making the operator unavailable and blaming the call site.
struct AutoScopeOpBox
{
    value: s32
}

impl AutoScopeOpBox
{
    mtd(op: Swag.Operator) const opBinary(other: AutoScopeOpBox)->AutoScopeOpBox
        where op == .Add
    {
        #static if op == .Addd do     // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
            return AutoScopeOpBox{.value + other.value}
        return AutoScopeOpBox{.value + other.value}
    }
}

#test
{
    let a = AutoScopeOpBox{1}
    let b = AutoScopeOpBox{2}

    // The overload is genuinely unusable once its body failed, so the call site reports too.
    @assert((a + b).value == 3)     // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    let y = .C     // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
}
