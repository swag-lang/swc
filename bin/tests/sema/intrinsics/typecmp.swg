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
