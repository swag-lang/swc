#global private
using Swag

func selectArrayInfo(flag: bool)->const *TypeInfoArray
{
    let info = flag ? #type const [2] f32 : #type const [2] s32
    #assert(#typeof(info) == const *TypeInfoArray)
    return cast(const *TypeInfoArray, info)
}

#test
{
    let trueInfo  = selectArrayInfo(true)
    let falseInfo = selectArrayInfo(false)
    Swag.require(trueInfo.count == 2)
    Swag.require(trueInfo.finalType == f32)
    Swag.require(falseInfo.count == 2)
    Swag.require(falseInfo.finalType == s32)
}
