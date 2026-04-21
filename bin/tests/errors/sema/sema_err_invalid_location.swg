#global fileprivate

// '#location' requires a symbol reference, not an expression or literal.
#test
{
    const a = #location(1 + 2)               // swc-expected-error {{sema_err_invalid_location}}
}

#test
{
    const b = #location(42)                  // swc-expected-error {{sema_err_invalid_location}}
}

#test
{
    const c = #location("string")            // swc-expected-error {{sema_err_invalid_location}}
}
