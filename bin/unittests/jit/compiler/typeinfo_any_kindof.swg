#global private
using Swag

struct AnyKindOfStruct
{
    x: s32
}

func anyKindOfFunc()->s32 => 1

#test
{
    func boxedTypeInfoKindof()->bool
    {
        let structBox: any = #typeof(AnyKindOfStruct)
        let funcBox:   any = #typeof(anyKindOfFunc)
        return @kindof(structBox) == const *TypeInfoStruct and
               @kindof(funcBox) == const *TypeInfoFunc and
               (cast(const *TypeInfoStruct) structBox).fields[0].name == "x" and
               (cast(const *TypeInfoFunc) funcBox).returnType == s32
    }

    @assert(boxedTypeInfoKindof())
}
