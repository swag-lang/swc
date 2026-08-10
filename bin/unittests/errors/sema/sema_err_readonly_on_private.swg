#global private

// 'private' already withholds every write from outside the declaring type, so 'readonly' on top
// of it restricts nothing.
struct Redundant
{
    private readonly value: s32     // swc-expected-error {{sema_err_readonly_on_private}}
}

// A bare 'readonly' rides on the level in effect, so an enclosing 'private' block reaches the
// same dead end.
struct RedundantBlock
{
    private
    {
        readonly value: s32     // swc-expected-error {{sema_err_readonly_on_private}}
    }
}
