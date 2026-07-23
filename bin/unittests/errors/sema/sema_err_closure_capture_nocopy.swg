#global private

#[Swag.NoCopy]
struct Handle
{
    x: s32
}

// A non-copyable type cannot be captured by value.
#test
{
    var h = Handle{1}
    var bad = func|h|()->s32 { return h.x }     // swc-expected-error {{sema_err_closure_capture_nocopy}}
}
