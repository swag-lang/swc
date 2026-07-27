#global private

struct LateInteger
{
    #[Swag.Late]
    value: s32     // swc-expected-error {{sema_err_late_bad_type}}
}

struct LateNullable
{
    #[Swag.Late]
    value: #null *s32     // swc-expected-error {{sema_err_late_bad_type}}
}
