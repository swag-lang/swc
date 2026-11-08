#global private

struct ClosureCaptureScopeOwner
{
    main: s32
}

impl ClosureCaptureScopeOwner
{
    mtd captureMain()->s32
    {
        let callback = func|main = .main|()->s32 => main     // swc-expected-error {{sema_err_cannot_compute_auto_scope}}
        return callback()
    }
}
