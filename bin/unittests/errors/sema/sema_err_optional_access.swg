#global private

// '?.' contract errors: the left side must actually be nullable, and the chain's
// result type must be able to carry the null outcome (or hand it to 'orelse').

struct OptionalAccessItem
{
    value: s32
    inner: OptionalAccessInner
}

struct OptionalAccessInner
{
    count: s64
}

func optionalAccessNeverNull(p: *OptionalAccessItem)->s32
{
    return p?.value orelse 0     // swc-expected-error {{sema_err_optional_access_not_nullable}}
}

func optionalAccessValueLeft(v: OptionalAccessItem)->s32
{
    return v?.value orelse 0     // swc-expected-error {{sema_err_optional_access_not_nullable}}
}

func optionalAccessScalarNoFallback(p: #null *OptionalAccessItem)->s32
{
    return p?.value     // swc-expected-error {{sema_err_optional_access_result_type}}
}

func optionalAccessStructResult(p: #null *OptionalAccessItem)->OptionalAccessInner
{
    return p?.inner     // swc-expected-error {{sema_err_optional_access_result_type}}
}
