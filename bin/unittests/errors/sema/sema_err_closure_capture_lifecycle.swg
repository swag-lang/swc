#global private

struct WithDrop
{
    x: s32
}

impl WithDrop
{
    mtd opDrop() {}
}

struct WithPostCopy
{
    x: s32
}

impl WithPostCopy
{
    mtd opPostCopy() {}
}

struct WithPostMove
{
    x: s32
}

impl WithPostMove
{
    mtd opPostMove() {}
}

// A struct containing a lifecycle-bearing field cannot be captured by value either.
struct Wrap
{
    inner: WithDrop
}

// A type with 'opDrop' cannot be captured by value.
#test
{
    var v = WithDrop{1}
    var bad = func|v|()->s32 { return v.x }     // swc-expected-error {{sema_err_closure_capture_lifecycle}}
}

// A type with 'opPostCopy' cannot be captured by value.
#test
{
    var v = WithPostCopy{2}
    var bad = func|v|()->s32 { return v.x }     // swc-expected-error {{sema_err_closure_capture_lifecycle}}
}

// A type with 'opPostMove' cannot be captured by value.
#test
{
    var v = WithPostMove{3}
    var bad = func|v|()->s32 { return v.x }     // swc-expected-error {{sema_err_closure_capture_lifecycle}}
}

// Lifecycle operations are contagious through fields.
#test
{
    var v = Wrap{}
    var bad = func|v|()->s32 { return v.inner.x }     // swc-expected-error {{sema_err_closure_capture_lifecycle}}
}
