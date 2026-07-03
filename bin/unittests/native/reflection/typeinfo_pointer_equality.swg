#global private
using Swag

func selectArrayTypeInfo(flag: bool)->const *Swag.TypeInfoArray
{
    if flag do
        return #typeof([1, 2.5])
    return #typeof([3.5, 4])
}

#test
{
    let infoTrue = selectArrayTypeInfo(true)
    let infoFalse = selectArrayTypeInfo(false)

    @assert(infoTrue == #type const [2] f32)
    @assert(infoFalse == #type const [2] f32)
    @assert(infoTrue.pointedType == f32)
    @assert(infoFalse.totalCount == 2)
}
