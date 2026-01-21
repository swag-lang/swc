#global internal

struct S {}

struct OkValue
{
    using v: S
}

struct OkPtr
{
    using p: *S
}

struct BadValue
{
    using v: s32 // swc-expected-error {{sema_err_using_member_type}}
}

struct BadPtr
{
    using p: *s32 // swc-expected-error {{sema_err_using_member_type}}
}
