#global private
using Swag

func conditionalArrayTypeInfo(flag: bool)->bool
{
    let info = flag ? #typeof([1, 2.5]) : #typeof([3.5, 4])
    let arrayInfo = cast(const *Swag.TypeInfoArray) info
    return info == #type const [2] f32 and
           arrayInfo.count == 2 and
           arrayInfo.totalCount == 2 and
           arrayInfo.pointedType == f32 and
           arrayInfo.finalType == f32
}

#test
{
    @assert(conditionalArrayTypeInfo(true))
    @assert(conditionalArrayTypeInfo(false))
}
