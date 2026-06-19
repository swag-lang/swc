#global fileprivate

func semaTest001()
{
    const a: typeinfo = s32
    @assert(@typecmp(a, a, .Strict))
}

func semaTest002()
{
    const a: typeinfo = s32
    @assert(@typecmp(a, a, .CastAny | .UnScoped))
}
