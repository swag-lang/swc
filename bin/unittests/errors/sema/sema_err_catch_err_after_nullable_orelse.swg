#global private

func catchNullableName(succeed: bool)->string? fail
{
    if not succeed do
        fail Swag.BaseError{"no name"}
    return null
}

func catchErrorCode()->s32 fail
{
    fail Swag.BaseError{"no code"}
}

func catchErrorName(error: any?)->string => error != null ? "error" : "none"

// A non-nullable result takes 'orelse V' only on failure, where 'Swag.err' exists.
#test
{
    let code = catch catchErrorCode() orelse cast(s32, Swag.err != null)
    Swag.assert(code == 1)
}

// A nullable result also takes it after a success that returns null, where no error exists.
#test
{
    let name = catch catchNullableName(true) orelse catchErrorName(Swag.err)     // swc-expected-error {{sema_err_catch_err_after_nullable_orelse}}
    discard name
}
