#global fileprivate

#test
{
    const a: typeinfo = s32
    @assert(@typecmp(a, a, .Strict))
}

#test
{
    const a: typeinfo = s32
    @assert(@typecmp(a, a, .CastAny | .UnScoped))
}

#test
{
    const a: typeinfo = s32
    let same = @typecmp(a, a, .Missing) // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
}
