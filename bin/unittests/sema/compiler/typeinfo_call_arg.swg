#global private

func takesType(t: typeinfo)->bool
{
    return t != null
}

func(T) takesGenericType()->bool
{
    return takesType(T)
}

func semaTest001()
{
    Swag.assert(takesType(s32))
    Swag.assert(takesType(#type s32))
    Swag.assert(takesGenericType's32())
}

#[Swag.Inline]
func takesType1(t: typeinfo)->bool
{
    return t != null
}

func(T) takesGenericType1()->bool
{
    return takesType1(T)
}

func semaTest002()
{
    Swag.assert(takesType1(s32))
    Swag.assert(takesType1(#type s32))
    Swag.assert(takesGenericType1's32())
}
