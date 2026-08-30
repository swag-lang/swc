#global private

struct ShortTypeInfoStruct
{
    x: s32
}

func shortTypeInfoFunc()->s32 => 1
func makeStructInfo()         => #typeof(ShortTypeInfoStruct)
func makeFuncInfo()           => #typeof(shortTypeInfoFunc)

#test
{
    let structInfo = makeStructInfo()
    let funcInfo   = makeFuncInfo()
    #assert(#typeof(structInfo) == const *TypeInfoStruct)
    #assert(#typeof(funcInfo) == const *TypeInfoFunc)
    Swag.assert(structInfo.fields![0].name == "x")
    Swag.assert(funcInfo.returnType == s32)
}
