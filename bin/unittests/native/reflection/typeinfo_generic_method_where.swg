#global private
using Swag

#[ConstExpr]
func typeCanCompare(type: typeinfo)->bool
{
    return type.kind != .Func and type.kind != .Lambda
}

#[Swag.ExportType(.Methods)]
struct(T) GenericLazyMethodBox
{
    value: s32
}

impl GenericLazyMethodBox
{
    mtd count()->s32
    {
        return 37
    }

    mtd defaultCompare(left, right: T)->s32
        where typeCanCompare(T)
    {
        return left <=> right
    }
}

func genericLazyMethodReflectionSkipsFailedWhere()->bool
{
    if typeCanCompare(#type func||()->s32)
    {
        return false
    }

    let info = cast(const *Swag.TypeInfoStruct, #typeof(GenericLazyMethodBox!{func||()->s32}))
    if info.methods.count < 1
    {
        return false
    }

    var hasCount = false
    var defaultCompareCallable = false
    for &methodInfo in info.methods
    {
        if methodInfo.name == "defaultCompare"
        {
            defaultCompareCallable = methodInfo.value != null
            continue
        }

        if methodInfo.name != "count"
        {
            continue
        }

        let methodType = assume cast(const *Swag.TypeInfoFunc?, methodInfo.pointedType)
        if methodType == null
        {
            return false
        }
        let params = methodType.parameters
        if methodType.kind != .Func or
           params == null or
           params.count != 1 or
           params[0].pointedType != #type *GenericLazyMethodBox!{func||()->s32} or
           methodType.returnType != s32
        {
            return false
        }

        hasCount = true
    }

    return hasCount and not defaultCompareCallable
}

#test
{
    Swag.require(genericLazyMethodReflectionSkipsFailedWhere())
}
