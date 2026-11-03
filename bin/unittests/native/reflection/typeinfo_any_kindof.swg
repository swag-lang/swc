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

    Swag.require(Swag.kindOf(structBox) == const *TypeInfoStruct)
    Swag.require(Swag.kindOf(funcBox) == const *TypeInfoFunc)
    Swag.require(assume cast (const *TypeInfoStruct, structBox).fields![1].name == "right")
    Swag.require(assume cast (const *TypeInfoFunc, funcBox).returnType == string)
}
