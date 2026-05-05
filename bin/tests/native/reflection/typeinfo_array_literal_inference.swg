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
    @assert(items[0] == #type func(TypeInfoArrayLiteralPoint)->bool)
    @assert(items[1] == #type func(TypeInfoArrayLiteralPoint)->bool)
    @assert(@countof(items[0].parameters) == 1)
    @assert(items[1].returnType == bool)
}
