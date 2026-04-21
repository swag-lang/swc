#global fileprivate

// A 'let' binding must be initialized at declaration.
#test
{
    let a: s32                   // swc-expected-error {{sema_err_let_missing_init}}
}

#test
{
    let b: bool                  // swc-expected-error {{sema_err_let_missing_init}}
}

#test
{
    let c: [3] s32               // swc-expected-error {{sema_err_let_missing_init}}
}
