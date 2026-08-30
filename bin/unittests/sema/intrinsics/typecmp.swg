#global private

func semaTest001()
{
    const a: typeinfo = s32
    Swag.assert(Swag.typeCmp(a, a, .Strict))
}

func semaTest002()
{
    const a: typeinfo = s32
    Swag.assert(Swag.typeCmp(a, a, .CastAny | .UnScoped))
}
