#global fileprivate
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
    let funcInfo: typeinfo = #typeof(nativeAnyKindOfFunc)
    let structBox: any = structInfo
    let funcBox: any = funcInfo

    @assert(@kindof(structBox) == const *TypeInfoStruct)
    @assert(@kindof(funcBox) == const *TypeInfoFunc)
    @assert((cast(const *TypeInfoStruct) structBox).fields[1].name == "right")
    @assert((cast(const *TypeInfoFunc) funcBox).returnType == string)
}
