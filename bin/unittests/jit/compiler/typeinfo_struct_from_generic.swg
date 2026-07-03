#global private
using Swag

struct(T) GenericBox
{
    value: T
}

func hasSharedGenericRoot()->bool
{
    let left  = cast(const *Swag.TypeInfoStruct) #typeof(GenericBox's32)
    let right = cast(const *Swag.TypeInfoStruct) #typeof(GenericBox'bool)

    return left.fromGeneric != null and
           right.fromGeneric != null and
           left.fromGeneric == right.fromGeneric and
           left.fromGeneric.name == "GenericBox"
}

#test
{
    @assert(hasSharedGenericRoot())
}
