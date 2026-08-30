struct TypeInfoArrayLiteralPoint
{
    x: s32
}

func typeInfoArrayLiteralAcceptsPoint(value: TypeInfoArrayLiteralPoint)->bool => value.x > 0
func typeInfoArrayLiteralRejectsPoint(value: TypeInfoArrayLiteralPoint)->bool => value.x < 0

#test
{
    let items = [#typeof(typeInfoArrayLiteralAcceptsPoint), #typeof(typeInfoArrayLiteralRejectsPoint)]

    #assert(#typeof(items) == [2] const *TypeInfoFunc)
    Swag.assert(items[0] == #type func(TypeInfoArrayLiteralPoint)->bool)
    Swag.assert(items[1] == #type func(TypeInfoArrayLiteralPoint)->bool)
    Swag.assert((items[0].parameters).count == 1)
    Swag.assert(items[1].returnType == bool)
}
