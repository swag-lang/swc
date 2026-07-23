#global private

struct LateInteger
{
    value: #late s32 // swc-expected-error {{sema_err_late_bad_type}}
}

struct LateNullable
{
    value: #late #null *s32 // swc-expected-error {{sema_err_late_bad_type}}
}
