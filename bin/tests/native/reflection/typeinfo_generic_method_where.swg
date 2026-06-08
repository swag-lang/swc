#global fileprivate
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
    if typeCanCompare(#type func||()->s32) do
        return false

    let info = cast(const *Swag.TypeInfoStruct) #typeof(GenericLazyMethodBox'func||()->s32)
    if @countof(info.methods) < 1 do
        return false

    var hasCount = false
    var defaultCompareCallable = false
    foreach &methodInfo in info.methods
    {
        if methodInfo.name == "defaultCompare"
        {
            defaultCompareCallable = methodInfo.value != null
            continue
        }

        if methodInfo.name != "count" do
            continue

        let methodType = cast(const *Swag.TypeInfoFunc) methodInfo.pointedType
        if methodInfo.pointedType.kind != .Func or
           @countof(methodType.parameters) != 1 or
           methodType.parameters[0].pointedType != #type &GenericLazyMethodBox'func||()->s32 or
           methodType.returnType != s32 do
            return false

        hasCount = true
    }

    return hasCount and !defaultCompareCallable
}

#test
{
    @assert(genericLazyMethodReflectionSkipsFailedWhere())
}
