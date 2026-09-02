#global private

// 'with' selects a value. A namespace or an enum names a scope, and 'using' is what brings a
// scope into the current context.
namespace WithScopeSubjectNs
{
    func helper() {}
}

enum WithScopeSubjectColor
{
    Red,
    Blue
}

#test
{
    with WithScopeSubjectNs     // swc-expected-error {{sema_err_with_scope_subject}}
    {
        .helper()
    }
}

#test
{
    with WithScopeSubjectColor     // swc-expected-error {{sema_err_with_scope_subject}}
    {
        let picked = .Red
        discard picked
    }
}
