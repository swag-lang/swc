#global private
using Swag

struct NativeAnyKindOfStruct
{
    left:  s32
    right: s32
}

func nativeAnyKindOfFunc(flag: bool)->string
{
    return flag ? "ok" : "ko"
}

#test
{
    let structInfo: typeinfo = #typeof(NativeAnyKindOfStruct)
    let funcInfo:   typeinfo = #typeof(nativeAnyKindOfFunc)
    let structBox:  any      = structInfo
    let funcBox:    any      = funcInfo

    Swag.assert(Swag.kindOf(structBox) == const *TypeInfoStruct)
    Swag.assert(Swag.kindOf(funcBox) == const *TypeInfoFunc)
    Swag.assert((cast(const *TypeInfoStruct) structBox).fields[1].name == "right")
    Swag.assert((cast(const *TypeInfoFunc) funcBox).returnType == string)
}
