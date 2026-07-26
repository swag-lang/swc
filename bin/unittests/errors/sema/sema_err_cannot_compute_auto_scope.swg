#global private

// An operator body is specialized with diagnostics on, except for the '#error' opt-out. A
// misspelled enum member is therefore reported instead of silently making the operator
// unavailable and blaming the call site.
struct AutoScopeOpBox
{
    value: s32
}

impl AutoScopeOpBox
{
    mtd(op: Swag.Operator) const opBinary(other: AutoScopeOpBox)->AutoScopeOpBox
    {
        #if op == .Addd do     // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
            return AutoScopeOpBox{.value + other.value}
        #else do
            #error("unsupported binary operation [[" ++ op.symbol() ++ "]]")
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
