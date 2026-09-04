#global private

struct LateInteger
{
    late value: s32     // swc-expected-error {{sema_err_late_bad_type}}
}

struct LateNullable
{
    late value: *s32?     // swc-expected-error {{sema_err_late_bad_type}}
}
